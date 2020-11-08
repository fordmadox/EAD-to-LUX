import json, jsonlines, logging
import jsonschema as jsonschema

from jsonschema import validate
from jsonschema import Draft7Validator

from pathlib import Path

# just loading this at the get go for now.
with open('/Users/markcuster/Documents/GitYale/json-schema-validation/schema.json') as f:
    schema = json.load(f)
    v = Draft7Validator(schema)

def get_ids(jsonData):
    for id in jsonData['identifiers']:
        if id['identifier_type'] == 'ead':
            fileId = id['identifier_value']
    return fileId

def validateJson(jsonData):
    try:
        fileId = get_ids(jsonData)
    except Exception as err:
        print(err)
        logging.info(err)
    try:
        validate(instance=jsonData, schema=schema)
    except jsonschema.exceptions.ValidationError as err:
        #only reports the first error in a file, but better than nothing (since i still need to read how this library works)
        logging.info("%s %s", fileId, err.message)
    return True

# to do... make logging work better.  just the error and filename should suffice.

def get_started():
    for file in Path('../ArchivesSpace-JSON-Lines').rglob('*.jsonl'):
        print(file.name)
        with jsonlines.open(file,'r') as reader:
            for obj in reader:
                validateJson(obj)

def main():
    logging.info('Started')
    get_started()
    logging.info('Finished')

if __name__ == '__main__':
    logging.basicConfig(filename='validation.log', level=logging.INFO, format='%(asctime)s %(message)s')
    logging.getLogger("jsonschema").setLevel(logging.INFO)
    main()
