<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:ead3="http://ead3.archivists.org/schema/"
    xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:saxon="http://saxon.sf.net/"
    xmlns:map="http://www.w3.org/2005/xpath-functions/map"
    xmlns:mdc="http://mdc"
    xmlns:j="http://www.w3.org/2005/xpath-functions" version="3.0">
    <!-- author(s): Mark Custer... you?  and you??? anyone else who wants to help! -->
    <!-- requires XSLT 3.0 -->
    <xsl:output method="text"/>
    
    <xsl:strip-space elements="*"/>
    <xsl:preserve-space elements="ead3:p"/>

    <xsl:include href="ead3-to-html.xsl"/>
    <xsl:include href="relators.xsl"/>
    <xsl:include href="collections_in_repositories.xsl"/>
    
    <xsl:key name="relator-code" match="relator" use="code"/>

    
    <!-- to do:
  
        review how languages are serialized once we upgrade.  
            can likely split out the notes better, if data is added to descriptiveNote moving forward.
            
        fix how the HTML conversion is handled.  no need to do silly text stuff. 
        
        finish usage rights
        
        include acquisition dates ???
        
        add onsite/offsite locations
            e.g. physloc localtype="whatever"
            (will also have a colleciton-level summary in a notestmt/controlnote in next round of exports)
        etc.
        
    -->
    <!-- 
        questions: 
            1) should everything aside from YCBA and Peabody get "Special Collections (YUL)" now?  this was the generic General Collection before.
            2) 

    -->
    
    
    <!-- now that we add @altrenders, should we change this function? -->
    <xsl:function name="mdc:find-the-ultimate-parent-id" as="xs:string">
        <!-- given that there can be multiple parent/id pairings, this occasionally recursive function will find and select the top container ID attribute, which will be used to do the groupings, rather than depenidng on entirely document order -->
        <xsl:param name="current-container" as="node()"/>
        <xsl:variable name="parent" select="$current-container/@parent"/>
        <xsl:choose>
            <xsl:when test="not($parent)">
                <xsl:value-of select="$current-container/@id"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:sequence select="mdc:find-the-ultimate-parent-id($current-container/preceding-sibling::ead3:container[@id eq $parent])"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>
    
    <xsl:function name="mdc:convert-to-date" as="xs:date">
        <xsl:param name="standarddate" as="xs:string"/>
        
        <xsl:variable name="date-numbers" select="for $num in tokenize($standarddate, '-') return number($num)"/>    
        <xsl:variable name="year">
            <xsl:value-of select="format-number($date-numbers[1], '0001')"/>
        </xsl:variable>
        <xsl:variable name="month">
            <xsl:value-of select="if ($date-numbers[2]) then format-number($date-numbers[2], '01') else '01'"/>
        </xsl:variable>
        <xsl:variable name="day">
            <xsl:value-of select="if ($date-numbers[3]) then format-number($date-numbers[3], '01') else '01'"/>
        </xsl:variable>           
        <xsl:variable name="date-string">
            <xsl:value-of select="$year, $month, $day" separator="-"/>
        </xsl:variable>  
        
        <xsl:value-of select="xs:date($date-string)"/>
        
    </xsl:function>
    
    <xsl:function name="mdc:convert-duration" as="xs:string">
        <xsl:param name="duration" as="node()"/>
        <!-- the label just specifies up to 3 milliseconds, so that's all we'll allow here, although there could certainly be more.
         -->
        <xsl:variable name="duration-statment" as="item()*">
            <xsl:analyze-string select="normalize-space($duration)" regex="^(\d\d):(\d\d):(\d\d\.?\d{{0,3}}$)">
                <xsl:matching-substring>
                    <xsl:variable name="hours" select="number(regex-group(1))"/>
                    <xsl:variable name="minutes" select="number(regex-group(2))"/>
                    <xsl:variable name="seconds" select="number(regex-group(3))"/>
                    <xsl:sequence select="(if ($hours eq 0) then ()
                        else $hours || ' hours', if ($minutes eq 0) then () else $minutes || ' minutes',
                        if ($seconds eq 0) then () else $seconds || ' seconds')"/>
                </xsl:matching-substring>
            </xsl:analyze-string>
        </xsl:variable>
        <xsl:value-of select="$duration-statment" separator=", "/>
    </xsl:function>

    <!-- 1) global parameters and variables -->
    <!-- 
        https://git.yale.edu/raw/LUX/json-schema-validation/master/schema.json
        
        https://git.yale.edu/mc2343/json-schema-validation/raw/master/schema.json
        
        /Users/markcuster/Documents/GitYale/json-schema-validation/schema.json
        
    -->
    <xsl:param name="json_schema_location" select="'https://git.yale.edu/raw/LUX/json-schema-validation/master/schema.json'"/>
    
    <xsl:param name="output-directory">
        <xsl:choose>
            <xsl:when test="$split-files">
                <xsl:value-of select="concat('../ArchivesSpace-JSON-Lines/', $repo-code, '/')"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:value-of select="concat('../ArchivesSpace-JSON/', $repo-code, '/', $collection-ID-text, '/')"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:param>
   
    
    <!-- change this to true to create one json file for each archival component, including the archdesc;
        when set to false, each EAD file produces a single json file for the archdesc.  not used when $split-files is set to true. -->
    <xsl:param name="include-dsc-in-transformation" select="true()"/>
    
    <!-- inherit container option.  might want to change this and add an open list for inheritible elements. currently not used. -->
    <xsl:param name="inherit-containers" select="true()"/>
    
    <!-- can be combined with system-id to get public uri -->
    <xsl:param name="base-url" select="'https://archives.yale.edu'"/>

    <xsl:param name="isPartOf-URI-prefix"/>
    
    <!-- don't have a good way to do this yet, but should include a switch for it.  right now, we always include it. -->
    <xsl:param name="includeHTML" select="true()"/>
    
    <xsl:param name="newline" select="'&#xa;'"/>
        
    <!-- this determines whether we go into JSON Lines mode or not.  pass false during testing. -->
    <xsl:param name="split-files" select="true()"/>
    <!-- this number determines the max number of lines in a JSON lines file.  we have a few collections with more than 10k, so we'll use that as a test case (we don't have any over 50k, though). -->
    <!-- was requested to change this to 5k -->
    <xsl:param name="split-at" as="xs:integer" select="5000"/>
    
    <!-- parameter for the serilization map, below.  
    for jsonl, though, we'll always keep this set to false... so, just adding two different variables for that now.
    for testing, we'll set to true()...-->
    <xsl:param name="indent" select="true()"/>
    
    <!-- note that saxon:property-order requires saxon pe or ee -->
    <!-- also, update this later since the only change is whether we indent or not!  should just update that one value when not using jsonlines -->
    <xsl:variable name="serialization-map" select="map{
        'method':'json',
        'encoding': 'utf-8',
        'indent': $indent,
        QName('http://saxon.sf.net/', 'property-order'): '$schema record identifiers basic_descriptors titles measurements notes languages agents places dates subjects locations rights digital_assets hierarchies * subject_facets supertypes',
        'use-character-maps': map{'/': '/'}}"/>
    
    <xsl:variable name="jsonl-serialization-map" select="map{
        'method':'json',
        'encoding': 'utf-8',
        'indent': false(),
        QName('http://saxon.sf.net/', 'property-order'): '$schema record identifiers basic_descriptors titles measurements notes languages agents places dates subjects locations rights digital_assets hierarchies * subject_facets supertypes',
        'use-character-maps': map{'/': '/'}}"/>
    
    <xsl:variable name="collection-ID" select="ead3:ead/ead3:control/ead3:recordid"/>
    <xsl:variable name="collection-ID-text" select="$collection-ID/normalize-space()"/>

    <xsl:variable name="collection-URI" select="$collection-ID/@instanceurl/normalize-space()"/>
    <xsl:variable name="repo-code" select="if (contains($collection-ID-text, '.')) then substring-before($collection-ID-text, '.') else null"/>
    <xsl:variable name="collection-call-number" select="ead3:ead/ead3:archdesc/ead3:did/ead3:unitid[not(@audience='internal')][1]/normalize-space()"/>
    <!-- also, YCBA-IA and OHAM (and Beinecke Ndy) use no separators.  in those cases, it's just code+number, eg. S001 -->
    <!-- could probably just grab the first character in those cases, but right now I still have no idea what they mean, if anything -->
    <xsl:variable name="curatorial-code-separator" select="if ($repo-code eq 'ypm') then '.' else ' '"/>
    <!-- need to change this logic for other edge cases, like Beinecke "NdyXXX" call numbers. for now, those just get added to Special Collections (YUL). -->
    <xsl:variable name="curatorial-code" select="$collection-call-number => substring-before($curatorial-code-separator) => upper-case()"/>
    
    <!-- consider changing to archdesc/did/repository, since the corpname element could actually have an @identifier attribute available there.  the publisher element, on the other hand, could only have an id attribute.-->
    <xsl:variable name="repository-name" select="ead3:ead/ead3:control/ead3:filedesc/ead3:publicationstmt/ead3:publisher[1]/normalize-space()"/>
    
    <!-- only 1 for the entire collection right now, but could add the archival object timestamps if needed if we add to the EAD3 exports -->
    <xsl:variable name="last-updated" select="ead3:ead/ead3:control/ead3:maintenancehistory/ead3:maintenanceevent[1]/ead3:eventdatetime[1]/replace(., '\+00:00', 'Z')"/>
    
    <!-- should everything from ASpace get this now, aside from YCBA and Peabody??? -->
    <xsl:variable name='default-general-collection-name' select="'Special Collections (YUL)'"/>
    
    <xsl:variable name="local-access-restriction-types" select="map{
        'RestrictedSpecColl': 'Donor/university imposed access restriction',
        'RestrictedCurApprSpecColl': 'Repository imposed access restriction',
        'RestrictedFragileSpecColl': 'Restricted fragile',
        'InProcessSpecColl': 'Restricted in-process',
        'UseSurrogate': 'Use surrogate'
        }"/>
    
    <xsl:variable name="did-note-type-label-backups" select="map{
        'abstract': 'Abstract',
        'dimensions': 'Dimensions',
        'langmaterial': 'Language',
        'materialspec': 'Material Details',
        'physdesc': 'Physical Description',
        'physfacet': 'Physical Facet',
        'physlocal': 'Physical Location'
        }"/>
    		
    <xsl:variable name="subject-facet-types" select="map{
        'agent_corporate_entity': 'organization',
        'agent_family': 'family',
        'agent_person': 'person',
        'cultural_context': 'culture',
        'genre_form': 'genre',
        'geographic': 'place',
        'temporal': 'period',
        'topical': 'topic',
        'uniform_title': 'title'
        }"/>
    
    <!-- not a label, i don't think, but that's the example from the spreadsheet documentation, so i'm going with it for now... -->
    <xsl:param name="default-metadata-rights-label" select="'CC0 1.0 Universal (CC0 1.0) Public Domain Dedication'"/>
    <xsl:param name="default-metadata-rights-URI" select="'https://creativecommons.org/publicdomain/zero/1.0/'"/>
    <xsl:param name="default-metadata-identifier-prefix" select="'aspace-'"/>
    
    <xsl:variable name="repo-email" select="ead3:ead/ead3:control[1]/ead3:filedesc[1]/ead3:publicationstmt[1]/ead3:address[1]/ead3:addressline[@localtype='email']"/>


    <!-- 2) primary template section -->
    <xsl:template match="ead3:ead">
        <xsl:if test="@audience='internal'">
            <xsl:message terminate="yes">
                <xsl:value-of select="$collection-ID-text"/> 
                <xsl:text> is unpublished, so we're skipping it.</xsl:text>
            </xsl:message> 
        </xsl:if>
        <xsl:if test="not($repo-code)">
            <xsl:message terminate="yes">
                <xsl:text>No recordid, so we're skipping this collection. Fix please!</xsl:text>
            </xsl:message> 
        </xsl:if>
        <xsl:choose>
            <xsl:when test="$split-files eq true()">             
                <xsl:for-each-group select="ead3:archdesc, ead3:archdesc/ead3:dsc//ead3:c" group-adjacent="(position() - 1) idiv $split-at">
                    <xsl:variable name="filename" select="$output-directory || $collection-ID-text || '-' || format-number(current-grouping-key() + 1, '000') || '.jsonl'"/>
                    <xsl:result-document href="{$filename}">
                        <xsl:apply-templates select="current-group()" mode="split-files"/>
                    </xsl:result-document>
                </xsl:for-each-group>
            </xsl:when>
            <xsl:otherwise>
                <xsl:apply-templates select="ead3:archdesc[not(@audience='internal')]"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>

    <!-- all components, including the archdesc, start here -->
    <!-- this process creates one file per level of description -->
    <!-- using ead3:c, but if we had to deal with both, could use a match for c, c0, c1 essentially-->
    <xsl:template match="ead3:archdesc | ead3:c">
        <xsl:param name="archdesc-level" select="if (local-name() eq 'archdesc') then true() else false()"/>
        <xsl:variable name="component-ID" select="if (@id)
                then $collection-ID-text || '-' || @id => normalize-space() => replace('aspace_', '')
                else $collection-ID-text || '-' || generate-id(.)"/>
        <xsl:variable name="component-name">
            <xsl:sequence select="ead3:did/ead3:unittitle[not(@audience='internal')]/string-join(normalize-space(.), '; ')"/>
        </xsl:variable>
        <xsl:variable name="filename">
            <xsl:choose>
                <xsl:when test="$archdesc-level eq true()">
                    <xsl:value-of select="$output-directory || $collection-ID-text || '.json'"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:value-of select="$output-directory || $component-ID || '.json'"/>
                </xsl:otherwise>
            </xsl:choose>
        </xsl:variable>
        <xsl:result-document href="{$filename}">
            <xsl:variable name="xml">
                <xsl:call-template name="create-xml">
                    <xsl:with-param name="archdesc-level" select="$archdesc-level"/>
                    <xsl:with-param name="component-name" select="$component-name"/>
                    <xsl:with-param name="component-ID" select="$component-ID"/>
                </xsl:call-template>
            </xsl:variable>
            <xsl:sequence select="$xml => xml-to-json() => parse-json() => serialize($serialization-map)"/>
        </xsl:result-document>
        <!-- when the include-dsc-in-transformation value is set to true, then all of the component templates will be processed by this same template recursively. -->
        <xsl:if test="$include-dsc-in-transformation eq true()">
            <xsl:apply-templates select="ead3:dsc/ead3:c[not(@audience='internal')] | ead3:c[not(@audience='internal')]"/>
        </xsl:if>
    </xsl:template>
    
    <xsl:template match="ead3:archdesc | ead3:c" mode="split-files">
        <xsl:param name="archdesc-level" select="if (local-name() eq 'archdesc') then true() else false()"/>
        <xsl:variable name="component-ID" select="if (@id)
            then $collection-ID-text || '-' || @id => normalize-space() => replace('aspace_', '')
            else $collection-ID-text || '-' || generate-id(.)"/>
        <xsl:variable name="component-name">
            <xsl:sequence select="ead3:did/ead3:unittitle[not(@audience='internal')]/string-join(normalize-space(.), '; ')"/>
        </xsl:variable>
        <xsl:variable name="xml">
            <xsl:call-template name="create-xml">
                <xsl:with-param name="archdesc-level" select="$archdesc-level"/>
                <xsl:with-param name="component-name" select="$component-name"/>
                <xsl:with-param name="component-ID" select="$component-ID"/>
            </xsl:call-template>
        </xsl:variable>
        <xsl:sequence select="$xml => xml-to-json() => parse-json() => serialize($jsonl-serialization-map)"/>  
        <!-- now that's what i call json lines, yeah -->
        <xsl:value-of select="$newline"/>
    </xsl:template>
 


    <!-- here's where we create the XML document in order to convert it to JSON.
    will eventually shorten this template by adding others, most likely.-->
    <xsl:template name="create-xml">
        <xsl:param name="component-name"/>
        <xsl:param name="archdesc-level"/>
        <xsl:param name="component-ID"/>

        <xsl:variable name="level-of-description" select="@level => lower-case() => normalize-space()"/>
        
        <!-- new, for Yale's updated EAD exporter in ASpace -->
        <xsl:variable name="aspace-id" select="@altrender"/>

        <!-- for us, we'll just have one of these.  we'll also expand these to include series identifiers at lower levels.  
            e.g. OSB MSS 176, Series I -->
        <!-- 
        string-join(ancestor::*[@level=('collection', 'recordgrp', 'series')]/did/unitid, ', ')
        plus add series id of current component.
        -->
        <xsl:variable name="EAD-unitid">
            <xsl:value-of select="if ($archdesc-level) then '' else ead3:did/ead3:unitid[not(@audience='internal')][1]/normalize-space()"/>
        </xsl:variable>
        
        <xsl:variable name="Voyager-BIB-ID" select="../ead3:control/ead3:otherrecordid[@localtype='BIB'][1]/normalize-space()"/>     
        
        <xsl:variable name="container-groupings">
            <xsl:for-each-group select="ead3:did/ead3:container" group-by="mdc:find-the-ultimate-parent-id(.)">
                <container-group>
                    <xsl:copy-of select="current-group()"/>
                </container-group>
            </xsl:for-each-group>
        </xsl:variable>
        
            
        <j:map>    
            <!-- schema declarartion -->
            <j:string key="$schema">
                <xsl:value-of select="$json_schema_location"/>
            </j:string>
                   
             
            <j:map key="record">
                <!-- field has been changed to the timestamp of LUX ingestion.... so, we don't know that any more.
                    because of that, we won't vend anything here, but leaving in the "last-updated" / exported from ASpace value in as an example.
                <j:string key="metadata_arrived_in_LUX">
                    <xsl:value-of select="$last-updated"/>
                </j:string>
                 -->
                <j:string key="metadata_identifier">
                    <xsl:value-of select="$default-metadata-identifier-prefix || replace($aspace-id, '^/repositories/\d*/', '') => replace('s/|_', '-')"/>
                </j:string>
                <j:string key="metadata_rights_label">
                    <xsl:value-of select="$default-metadata-rights-label"/>
                </j:string>
                <j:array key="metadata_rights_URI">
                    <j:string>
                        <xsl:value-of select="$default-metadata-rights-URI"/>
                    </j:string>
                </j:array>
            </j:map>
                      
            <!-- identifiers -->
           <j:array key="identifiers">
               <j:map>
                   <j:string key="identifier_value">
                       <xsl:choose>
                           <xsl:when test="$archdesc-level and $collection-ID">
                               <xsl:value-of select="$collection-ID"/>
                           </xsl:when>
                           <xsl:otherwise>
                               <xsl:value-of select="$component-ID"/>
                           </xsl:otherwise>
                       </xsl:choose>
                   </j:string>
                   <j:string key="identifier_type">
                       <xsl:text>ead</xsl:text>
                   </j:string>
               </j:map>
               <j:map>
                   <j:string key="identifier_value">
                       <xsl:value-of select="$collection-call-number"/>
                   </j:string>
                   <j:string key="identifier_display">
                       <xsl:value-of select="$collection-call-number"/>
                   </j:string>
                   <j:string key="identifier_type">
                       <xsl:value-of select="'call number'"/>
                   </j:string>
                   <j:string key="identifier_label">
                       <xsl:text>Call Number</xsl:text>
                   </j:string>
               </j:map>
               <xsl:for-each select="ancestor::ead3:c[not(@audience='internal')][@level=('collection', 'fonds', 'recordgrp', 'series')][ead3:did/ead3:unitid/normalize-space()]">
                   <j:map>
                       <j:string key="identifier_value">
                           <xsl:value-of select="ead3:did/ead3:unitid/normalize-space()"/>
                       </j:string>
                       <j:string key="identifier_type">
                           <xsl:value-of select="@level || ' unitid'"/>
                       </j:string>
                   </j:map>
               </xsl:for-each>
               <xsl:if test="$EAD-unitid != '' and not($archdesc-level)">
                   <j:map>
                       <j:string key="identifier_value">
                           <xsl:value-of select="$EAD-unitid"/>
                       </j:string>
                       <j:string key="identifier_display">
                           <xsl:value-of select="$EAD-unitid"/>
                       </j:string>
                       <j:string key="identifier_type">
                           <xsl:text>unitid</xsl:text>
                       </j:string>
                       <j:string key="identifier_label">
                           <xsl:value-of select="if ($EAD-unitid) then 'Identifier' else ()"/>
                       </j:string>
                   </j:map>
               </xsl:if>      
               <xsl:if test="$Voyager-BIB-ID">
                   <j:map>
                       <!-- adding "yul:" as per the YUL examples -->
                       <j:string key="identifier_value">
                           <xsl:value-of select="'yul:' || $Voyager-BIB-ID"/>
                       </j:string>
                       <j:string key="identifier_type">
                           <xsl:text>voyager bib id</xsl:text>
                       </j:string>
                   </j:map>
               </xsl:if>
           </j:array>
            
            
            <!-- basic descriptors (not a grouping element) -->
            <j:map key="basic_descriptors">
                <xsl:call-template name="supertypes"/>
                <!--
                <j:string key="edition_display"/>
                <j:string key="imprint_display"/>
                -->
                
                <!-- what could we map here??? 
                <j:array key="materials_display"/>
                -->
                
                <!-- used to go to notes, now mapping here since these have been untangled from rights -->
                <j:array key="provenance_display">
                    <xsl:apply-templates select="ead3:custodhist" mode="array-wrapped-notes"/>
                </j:array>
                <j:array key="acquisition_source_display">
                    <xsl:apply-templates select="ead3:acqinfo" mode="array-wrapped-notes"/>
                </j:array>           
            </j:map>

            <!-- titles -->
            <j:array key="titles">
                <!-- don't need all of this internal stuff since we already process the EAD, but what the hay -->
                <xsl:call-template name="combine-title-and-date"/>
            </j:array>
            
            <!--measurements
                what to map here?? -->
            <!-- since this field is no longer required, i don't need to "values?" param anymore -->
            <xsl:if test="ead3:did/ead3:physdescstructured">
                <j:array key="measurements">
                    <xsl:apply-templates select="ead3:did/ead3:physdescstructured" mode="measurements"/>
                </j:array>
            </xsl:if>
            
            <!-- notes (plus container info, for now) -->
            <j:array key="notes">
                    <xsl:apply-templates select="$container-groupings/container-group"/>
                    <xsl:apply-templates select="
                        ead3:did/ead3:abstract | 
                        ead3:did/ead3:dimensions (: add elsewhere? :) |                        
                        ead3:did/ead3:langmaterial[ead3:descriptivenote] |  (: language codes/values are passed to the langauges array. here, we just grab any other notes. :)
                        ead3:did/ead3:materialspec |
                        ead3:did/ead3:physdesc[not(@localtype='container_summary')] (: definitely elsewhere :) |
                        ead3:did/ead3:physfacet |
                        ead3:did/ead3:physloc |
                        ead3:accruals | 
                        ead3:altformavail |
                        ead3:appraisal | 
                        ead3:arrangement | 
                        ead3:bibliography |
                        ead3:bioghist |
                        ead3:fileplan |
                        ead3:index |
                        ead3:legalstatus |
                        ead3:odd | 
                        ead3:originalsloc |
                        ead3:otherfindaid |
                        ead3:phystech |
                        ead3:prefercite |
                        ead3:processinfo |
                        ead3:relatedmaterial |
                        ead3:scopecontent |
                        ead3:separatedmaterial" mode="notes"/> 
            </j:array>
            
            <!-- languages -->
            <j:array key="languages">
                <!-- either need a note note here, or just continue to pass the langmaterial/descriptivenote to the notes array -->
                <xsl:apply-templates select="ead3:did/ead3:langmaterial/ead3:language" mode="languages"/>
            </j:array>
                   
            <!-- agents -->
            <j:array key="agents">
                <xsl:apply-templates select="ead3:did/ead3:origination"/>
            </j:array>
                     
            <!-- places -->
            <!-- what to map here?  probably can only map our geogrpahic headings as subjects... and 
                those could really be subjects and not "places", with specific roles, associated with the material
            <j:array key="places">
                <j:map>
                    <j:string key="place_display"/>
                    <j:array key="place_URI"/>
                    <j:string key="place_role_label"/>
                    <j:string key="place_role_code"/>
                    <j:array key="place_role_URI"/>
                    <j:string key="place_type_display"/>
                    <j:array key="place_type_URI"/>
                    <j:array key="place_coordinates_display"/>
                    <j:array key="place_coordinates_type"/>
                </j:map>
            </j:array>
            -->
            
            <!-- dates -->
            <j:array key="dates">
                <xsl:apply-templates select="ead3:did/ead3:unitdate | ead3:did/ead3:unitdatestructured"/>
            </j:array>
            
            <!-- subjects -->
            <j:array key="subjects">
                <!-- we don't need to worry about ead3:controlaccess/ead3:head or anything else like that..  just the subjects! -->
                <!-- update this if we map the geognames to 'places' instead.  maybe only geognames with a single part? -->
                <xsl:apply-templates select="ead3:controlaccess/*" mode="subjects"/>
            </j:array>
            
            <!-- locations -->
            <j:array key="locations">
                <j:map>
                    <!-- hopefully we can change the names when the JSON schema is revised -->
                    <j:array key="campus_division">
                        <j:string>
                            <xsl:value-of select="if ($repo-code eq 'ypm') then 'Yale Peabody Museum of Natural History' 
                                else if ($repo-code eq 'ycba') then 'Yale Center for British Art'
                                else 'Yale University Library'"/>
                        </j:string>
                    </j:array>
                    
                    <!-- what about YCBA, Peabody?  just leave out, right? -->
                    <j:array key="yul_holding_institution">
                        <xsl:if test="not($repo-code = ('ypm', 'ycba'))">
                            <j:string>
                                <xsl:value-of select="if (contains($repository-name, 'Arts Library')) then 'Haas Arts Library' else $repository-name"/>
                            </j:string>
                        </xsl:if>
                    </j:array>
                    
                    <xsl:call-template name="collections"/>
                    
                    <!-- could do something here about on-site vs. off-site, but need guidance on this. ditto for a lot of stuff here. -->
                    <j:array key="access_in_repository_display">
                        <j:map>
                            <j:string key="value">
                                <xsl:apply-templates select="ead3:did" mode="access_notes"/>
                            </j:string>
                        </j:map>
                        
                    </j:array>
                    
                    <j:array key="access_in_repository_URI">
                        <j:string>
                            <xsl:value-of select="$base-url || $aspace-id"/>
                        </j:string>
                    </j:array>
                    
                    <!-- email or webpage -->
                    <j:string key="access_contact_in_repository">
                       <xsl:value-of select="$repo-email"/>
                    </j:string>
                    
                </j:map>          
            </j:array>
            
            <j:array key="rights">
                <xsl:call-template name="rights"/>
            </j:array>
            
            <!-- exclude this key if there are none??? -->
            <!-- also, this data model doesn't work very well for ASpace.  ASpace can have digital object sets, but LUX cannot.
                i think the main use case here is digital object links, thumbnails, and outbound links to metadata (e.g. IIIF manifests).
                propose a simplification for digital_assets in the next revision -->
            <j:array key="digital_assets">
                <xsl:apply-templates select="ead3:did/ead3:daoset/ead3:dao[@href]| ead3:did/ead3:dao[@href]"/>
            </j:array>
            
            <!-- hierarchies -->
            <j:array key="hierarchies">
                <xsl:variable name="level-of-description">
                    <xsl:choose>      
                        <xsl:when test="$archdesc-level">
                            <xsl:text>Collection</xsl:text>
                        </xsl:when>
                        <xsl:otherwise>
                            <xsl:sequence select="if ($level-of-description eq 'recordgrp') then 'Record Group'
                                else if ($level-of-description eq 'subgrp') then 'Subgroup'
                                else if ($level-of-description eq 'otherlevel') then concat(upper-case(substring(@otherlevel,1,1)),
                                substring(@otherlevel, 2),
                                ' '[not(last())])
                                else concat(upper-case(substring($level-of-description,1,1)),
                                substring($level-of-description, 2),
                                ' '[not(last())])"/>
                        </xsl:otherwise>
                    </xsl:choose>
                </xsl:variable>
                <!-- might need to be a bit more robust here....  could add an option to inherit containers? -->
                <!-- is that hacky test sufficient to work for peabody finding aids that don't have containers? -->
                <xsl:variable name="deliverable-unit-test" select="if (ead3:did/ead3:container | 
                    ead3:did/ead3:dao and not(ead3:c) or (not(ead3:c) and $repo-code eq 'ypm')) then '; Deliverable Unit' else ()"/>
                <j:map>
                    <j:string key="hierarchy_type">
                        <xsl:value-of select="'EAD' || '; ' || $level-of-description || $deliverable-unit-test"/>
                    </j:string>
                    <j:string key="root_internal_identifier">
                        <xsl:value-of select="$base-url || (if (self::ead3:archdesc) then $aspace-id else ancestor-or-self::ead3:archdesc/@altrender)"/>
                    </j:string>
                    <j:number key="descendant_count">
                        <xsl:value-of select="count(descendant::ead3:c)"/>
                    </j:number>
                    <!-- what's the real definition of this?  should it be max depth of the collection, or max depth of the context node? -->
                    <!-- let's go with context node.  you can always get the max max depth from the collection/archdesc node -->
                    <j:number key="maximum_depth">
                        <xsl:variable name="current-max-depth" select="(max(descendant::ead3:c[not(ead3:c)]/count(ancestor::ead3:c)), 0)[1]" as="xs:integer"/>
                        <!-- only add archdesc to the ancestor count if there are any components -->
                        <xsl:value-of select="if (self::ead3:archdesc and $current-max-depth ne 0) then $current-max-depth + 1 else $current-max-depth"/>
                    </j:number>
                    <j:number key="sibling_count">
                        <xsl:value-of select="if (self::ead3:archdesc) then 0 else count(../ead3:c) - 1"/>
                    </j:number>
                    
                    <!-- add the ASpace stuff here -->
                    <j:array key="ancestor_internal_identifiers">
                        <xsl:apply-templates select="ancestor::*[local-name() = ('archdesc', 'c')]/@altrender" mode="ancestor-array"/>
                    </j:array>
                        
                    <!-- not used, but adding since it's required by the json schema -->
                    <j:array key="ancestor_URIs"/>
                        
                    <j:array key="ancestor_display_names">
                        <xsl:apply-templates select="ancestor::*[local-name() = ('archdesc', 'c')]/ead3:did" mode="ancestor-array"/>
                    </j:array>
                             
                </j:map>
            </j:array>
            
            <!-- citations array would go here, but need to figure out how / if we can map this.  for Papyrus, we should have something to map,
                but not sure if / how to use ead3:bibliography here.  need to evaluate data / ask staff -->
        </j:map>
    </xsl:template>

    <!-- EAD mappings -->
    
    <xsl:template match="@altrender" mode="ancestor-array">
        <j:string>
            <xsl:value-of select="$base-url || ."/>
        </j:string>
    </xsl:template>
    
    <xsl:template match="ead3:did" mode="ancestor-array">
        <j:string>
            <xsl:if test="../@level = 'series' and ead3:unitid">
                <xsl:value-of select="ead3:unitid/normalize-space() || '. '"/>
            </xsl:if>
            <xsl:choose>
                <xsl:when test="ead3:unittitle">
                    <!-- we can only have one, but update if that ever changes in ASpace -->
                    <xsl:apply-templates select="ead3:unittitle" mode="#current"/>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:apply-templates select="ead3:unitdate | ead3:unitdatestructured" mode="add-dates-to-title"/>
                </xsl:otherwise>
            </xsl:choose>
        </j:string>
    </xsl:template>
    
    <!-- would it be better to create a variable with the notes?? -->
    <xsl:template match="ead3:did" mode="access_notes">
        <xsl:call-template name="access_notes">
            <xsl:with-param name="repo-code" select="$repo-code"/>
            <xsl:with-param name="collection-URI" select="$collection-URI"/>
        </xsl:call-template>  
    </xsl:template>
    
    <xsl:template name="combine-title-and-date">
        <!-- also need to deal with inherited titles here.  e.g. if not ead3:did/ead3:unittitle,
            specify type = 'inherited'
            and grab archival object or archdesc title -->
        <xsl:variable name="inherited" select="if (not(ead3:did/ead3:unittitle[not(@audience='internal')])) then true() else false()" as="xs:boolean"/>
        <j:map>   
            <j:array key="title_display">
                <j:map>
                    <j:string key="value">
                        <xsl:apply-templates select="if ($inherited) 
                            then ancestor::ead3:*[ead3:did/ead3:unittitle][1]/ead3:did/ead3:unittitle
                            else ead3:did/ead3:unittitle"/>
                        <!-- if no title, ASpace requires a date, but let's add a check regardless -->
                        <xsl:if test="ead3:did/ead3:unitdate | ead3:did/ead3:unitdatestructured">
                            <xsl:text>, </xsl:text> 
                        </xsl:if>
                        <xsl:apply-templates select="ead3:did/ead3:unitdate | ead3:did/ead3:unitdatestructured" mode="add-dates-to-title"/>
                    </j:string>
                </j:map>
            </j:array>
            <j:string key="title_type">
                <xsl:value-of select="if ($inherited) then 'inherited' else 'primary'"/>
            </j:string>
            <j:string key="title_label">
                <xsl:value-of select="'Primary'"/>
            </j:string>
        </j:map>
    </xsl:template>
    
    <xsl:template name="rights">
        <xsl:apply-templates select="ead3:accessrestrict | ead3:userestrict"/>        
    </xsl:template>
    
    <xsl:template name="sub-rights-fields">
        <j:array key="original_rights_URI">
            <j:string>
                <xsl:value-of select="if ($repo-code = 'beinecke' and self::ead3:userestrict) 
                    then 'https://beinecke.library.yale.edu/research-teaching/copyright-questions' 
                    else ''"/>
                <!-- follow up on this with all of the repos -->
            </j:string>
        </j:array>
    </xsl:template>
    
    <xsl:template name="supertypes">
        <j:array key="supertypes">
            <!-- default for everything described in ASpace, for now -->
            <j:array>  
                <j:string>Archival and Manuscript Material</j:string>
            </j:array>
                          
            <!-- DRY this up and move to a function or named template once we have the full set of mappings -->
            <xsl:if test="some $t in ead3:did/ead3:physdescstructured/ead3:unittype satisfies matches($t, 'audio|phonograph', 'i')">
                <j:array> 
                    <j:string>Time-Based Media</j:string>
                    <j:string>Audio</j:string>
                </j:array>
            </xsl:if>
            <xsl:if test="some $t in ead3:did/ead3:physdescstructured/ead3:unittype satisfies matches($t, 'video|film', 'i')">
                <j:array>  
                    <j:string>Time-Based Media</j:string>
                    <j:string>Moving Images</j:string>
                </j:array>
            </xsl:if>       
            <xsl:if test="some $t in ead3:did/ead3:physdescstructured/ead3:unittype satisfies matches($t, 'painting', 'i')">
                <j:array>  
                    <j:string>Two-Dimensional Objects</j:string>
                    <j:string>Paintings</j:string>
                </j:array>
            </xsl:if>
            <xsl:if test="some $t in ead3:did/ead3:physdescstructured/ead3:unittype satisfies matches($t, 'photo', 'i')">
                <j:array>  
                    <j:string>Two-Dimensional Objects</j:string>
                    <j:string>Photographs</j:string>
                </j:array>
            </xsl:if>
        </j:array>
    </xsl:template>
    
    <xsl:template match="ead3:accessrestrict | ead3:userestrict">
        <j:map>
            <j:string key="original_rights_status_display">
                <!-- we can't really do anything with userestrict here, right? -->
                <xsl:if test="self::ead3:accessrestrict">
                    <xsl:value-of select="for $t in tokenize(@localtype, ' ') 
                        return map:get($local-access-restriction-types, $t)" separator="; "/>                 
                </xsl:if>
            </j:string>
            
            <!-- woops.  shouldn't have made this required in v9 of the JSON schema. -->
            <j:array key="original_rights_copyright_credit_display">
                <j:map>
                    <j:string key="value"/>
                </j:map>
            </j:array>
            
            <!-- this is difficult to untangle, since we have access vs. use notes.  will likely need to consult with staff and come up with mapping logic-->
            <j:array key="original_rights_notes">
                <j:string>
                    <xsl:apply-templates/>
                </j:string>
            </j:array>
            
            <j:string key="original_rights_type">
                <xsl:value-of select="if (self::ead3:accessrestrict) then 'access' else 'usage'"/>
            </j:string>
            
            <!-- more sighs -->
            <j:string key="original_rights_type_label">
                <xsl:value-of select="if (self::ead3:accessrestrict) then 'Access' else 'Usage'"/>
            </j:string>
            
            <xsl:call-template name="sub-rights-fields"/>
        </j:map>
    </xsl:template>
    
    <!-- digital_assets stuff, but just for the daos that we're mapping currently -->
    <xsl:template match="ead3:dao">
        <xsl:variable name="primary" as="xs:boolean">
            <xsl:value-of select="if (count(../preceding-sibling::ead3:daoset) eq 0) then true()
                else if (parent::ead3:did and count(preceding-sibling::ead3:dao) eq 0) then true() else false()"/>
        </xsl:variable>
        <j:map>
            <!-- 
        optional properties:  data not stored in ASpace, so not vending currently
            asset_rights_status_display     / string
            asset_rights_notes              / array string
            asset_rights_type               / string
            asset_rights_type_label         / string
            asset_type                      / string (might be able to add this from ASpace, but folks currently don't record it)
         -->
            <j:array key="asset_URI">
                <j:string>
                    <xsl:value-of select="@href"/>
                </j:string>
            </j:array>
            <xsl:if test="@show eq 'embed' and $primary">
                <j:string key="asset_flag">
                    <xsl:value-of select="'primary image'"/>
                </j:string>
            </xsl:if>
            <xsl:if test="@linktitle">
                <j:array key="asset_caption_display">
                    <j:map>
                        <j:string key="value">
                            <xsl:value-of select="@linktitle"/>
                        </j:string>
                    </j:map>
                </j:array>
            </xsl:if>
            <j:string key="asset_type">
                <xsl:value-of select="if (@show eq 'embed') then 'thumbnail' else if (starts-with(@href, 'https://soundcloud')) then 'soundcloud' else 'digital object link'"/>
            </j:string>
        </j:map>  
    </xsl:template>
    
    <!-- add all the notes here, aside from the ones that are mapped elsewhere -->
    <xsl:template match="ead3:*" mode="notes">
        <j:map>
            <j:array key="note_display">
                <!-- don't have the ablity in ASpace to denote different languages and descriptions, aside from at the finding-level, so right now
                leaving out those options and just providing the display "value".-->
                <j:map>
                    <j:string key="value">
                        <!-- note that we are currently suppressing "ead3:head", but better to be more explicit here in the transformation.-->
                        <xsl:apply-templates select="if (local-name() = ('langmaterial')) then ead3:descriptivenote else (text() | * except ead3:head)"/>
                    </j:string>  
                </j:map>
            </j:array>
            <j:string key="note_type">
                <xsl:value-of select="local-name()"/>
            </j:string>
            <j:string key="note_label">
                <xsl:value-of select="if (ead3:head) then ead3:head[1]/normalize-space()
                    else if (@label) then normalize-space(@label) 
                    else if (map:contains($did-note-type-label-backups, local-name())) then map:get($did-note-type-label-backups, local-name())
                    else ()"/>
            </j:string> 
        </j:map>
    </xsl:template>
    
    <!-- just "acqinfo" and "custodhist" currently, both of which are mapped to "basic_descriptors" -->
    <xsl:template match="ead3:*" mode="array-wrapped-notes">
        <j:map>
            <!-- don't have the ablity in ASpace to denote different languages and descriptions, aside from at the finding-level, so right now
                leaving out those options and just providing the display "value".-->
            <j:string key="value">
                <xsl:apply-templates select="text() | * except ead3:head"/>
            </j:string>
        </j:map>
    </xsl:template>
    
    <xsl:template match="ead3:language" mode="languages">
        <j:map>
            <!-- prolly gotta do something for notes that have text -->
            <j:string key="language_display">
                <xsl:apply-templates/>
            </j:string>
            <j:string key="language_code">
                <xsl:value-of select="normalize-space(@langcode)"/>
            </j:string>
            <j:array key="language_URI">
                <j:string>
                    <xsl:value-of select="if (@langcode) then 'http://id.loc.gov/vocabulary/languages/' || normalize-space(@langcode) else ''"/>
                </j:string>
            </j:array>
            <!-- advocate for scriptcodes, too, or agree to use IETF BCP 47 and add to language_code above? -->
        </j:map>
    </xsl:template>
    
    <xsl:template match="ead3:origination">
        <xsl:variable name="relator" select="*/normalize-space(@relator)"/>
        <j:map>
            <j:array key="agent_display">
                <j:map>
                    <j:string key="value">
                        <xsl:apply-templates/>
                    </j:string>
                </j:map>
            </j:array>
            <j:string key="agent_sortname">
                <xsl:apply-templates/>
            </j:string>
            <j:array key="agent_URI">
                <j:string>
                    <xsl:value-of select="*/normalize-space(@identifier)"/>
                </j:string>
            </j:array>
            <j:string key="agent_role_label">
                <xsl:choose>
                    <xsl:when test="$relator">
                        <xsl:value-of select="key('relator-code', $relator, $cached-list-of-relators)/label"/>
                    </xsl:when>
                    <!-- should parameratize the Creator/Contributor so that they are configuration options, but just adding them as is for now -->
                    <xsl:when test="lower-case(@label) eq 'source'">
                        <xsl:value-of select="'Source'"/>
                    </xsl:when>
                    <xsl:when test="(lower-case(@label) eq 'creator') and not(preceding-sibling::ead3:origination[lower-case(@label) eq 'creator'])">
                        <xsl:value-of select="'Creator'"/>
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:value-of select="'Contributor'"/>
                    </xsl:otherwise>
                </xsl:choose>     
            </j:string>
            <j:string key="agent_role_code">
                <xsl:value-of select="$relator"/>
            </j:string>
            <j:array key="agent_role_URI">
                <j:string>
                    <xsl:if test="$relator">
                        <xsl:value-of select="'http://id.loc.gov/vocabulary/relators/' || $relator"/>
                    </xsl:if>
                </j:string>
            </j:array>
            <j:string key="agent_type_display">
                <xsl:choose>
                    <xsl:when test="ead3:persname">
                        <xsl:text>person</xsl:text>
                    </xsl:when>
                    <xsl:when test="ead3:corpname">
                        <xsl:text>organization</xsl:text>
                    </xsl:when>
                    <xsl:when test="ead3:famname">
                        <xsl:text>family</xsl:text>
                    </xsl:when>
                    <xsl:otherwise>
                        <!-- in ASpace, it would default to Software, but let's say Unknown for now since it would likely be  mistake if indicated as such -->
                        <xsl:text>unknown</xsl:text>
                    </xsl:otherwise>
                </xsl:choose>
                <!-- or just filter out sources from LUX? -->
            </j:string>
            <j:array key="agent_type_URI">
                <j:string>
                    <xsl:choose>
                        <xsl:when test="ead3:persname">
                            <xsl:text>http://id.loc.gov/ontologies/bibframe/Person</xsl:text>
                        </xsl:when>
                        <xsl:when test="ead3:corpname">
                            <xsl:text>http://id.loc.gov/ontologies/bibframe/Organization</xsl:text>
                        </xsl:when>
                        <xsl:when test="ead3:famname">
                            <xsl:text>http://id.loc.gov/ontologies/bibframe/Family</xsl:text>
                        </xsl:when>
                        <!-- in ASpace, it would default to Software, but let's just keep this blank for now -->
                        <xsl:otherwise/>
                    </xsl:choose>
                </j:string>
            </j:array>
            <!-- ask if this should be a number... and whether we start at 0, 1, or whatever -->
            <j:string key="agent_sort">
                <xsl:value-of select="position()"/>
            </j:string>
        </j:map>
    </xsl:template>
    
    <xsl:template match="ead3:unitdate | ead3:unitdatestructured" mode="add-dates-to-title">
        <xsl:if test="@unitdatetype eq 'bulk' and not(contains(lower-case(.), 'bulk'))">
            <xsl:text>bulk </xsl:text>
        </xsl:if>
        <xsl:choose>
            <xsl:when test="@altrender">
                <xsl:value-of select="normalize-space(@altrender)"/>
            </xsl:when>
            <xsl:when test="self::ead3:unitdate">
                <xsl:value-of select="translate(., '-', '&#x2013;')"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:apply-templates mode="#current"/>
            </xsl:otherwise>
        </xsl:choose>
        <xsl:if test="position() ne last()">
            <xsl:text>, </xsl:text>
        </xsl:if>
    </xsl:template>
    
    <!-- really need to review all of the EAD3 possibilities, but pretty sure that ASpace limits those quite a bit -->
    <!-- need to use datatypes like  xs:gYear
        or fine to just use number? -->
   <xsl:template match="ead3:unitdate | ead3:unitdatestructured">
       <xsl:variable name="current-node-name" select="self::*/local-name()"/>
       <!-- capitalize the @label -->
       <!-- note:  serializing the date types to @label right now, but should update to use @datechar instead. -->
       <xsl:variable name="date_role_label" select="if (@label eq 'creation') then 'Created' else concat(upper-case(substring(@label,1,1)),
               substring(@label, 2),
               ' '[not(last())])"/>
       
       <xsl:variable name="date_earliest" as="xs:date?">
           <xsl:choose>
               <xsl:when test="$current-node-name eq 'unitdatestructured' and descendant::ead3:*/@standarddate">
                   <xsl:value-of select="min(descendant::ead3:*[@standarddate]/mdc:convert-to-date(@standarddate))"/>
               </xsl:when>
               <xsl:when test="$current-node-name eq 'unitdate' and @normal">
                   <xsl:value-of select="(if (contains(@normal, '/')) then substring-before(@normal, '/') else @normal) => mdc:convert-to-date()"/>
               </xsl:when>
           </xsl:choose>
       </xsl:variable>
       <xsl:variable name="date_latest" as="xs:date?">
           <xsl:choose>                  
               <xsl:when test="$current-node-name eq 'unitdatestructured' and descendant::ead3:*/@standarddate">
                   <xsl:value-of select="max(descendant::ead3:*[@standarddate]/mdc:convert-to-date(@standarddate))"/>
               </xsl:when>
               <xsl:when test="$current-node-name eq 'unitdate' and contains(@normal, '/')">
                   <xsl:value-of select="substring-after(normalize-space(@normal), '/') => mdc:convert-to-date()"/>
               </xsl:when>
           </xsl:choose>
       </xsl:variable>
       
       <j:map>
           <j:array key="date_display">
               <j:map>
                   <j:string key="value">
                       <xsl:choose>
                           <xsl:when test="@altrender">
                               <xsl:value-of select="normalize-space(@altrender)"/>
                           </xsl:when>
                           <xsl:when test="$current-node-name eq 'unidate'">
                               <xsl:value-of select="translate(., '-', '&#x2013;')"/>
                           </xsl:when>
                           <xsl:otherwise>
                               <xsl:apply-templates/>
                           </xsl:otherwise>
                       </xsl:choose>
                   </j:string>
               </j:map>
           </j:array>
           <xsl:if test="$date_earliest castable as xs:date">
               <j:string key="date_earliest">
                   <xsl:value-of select="$date_earliest"/>
               </j:string>
               <j:string key="year_earliest">
                   <xsl:value-of select="$date_earliest => year-from-date() => format-number('0000')"/>
               </j:string>
           </xsl:if>
           <xsl:if test="$date_latest castable as xs:date">
               <j:string key="date_latest">
                   <xsl:value-of select="$date_latest"/>
               </j:string>
               <j:string key="year_latest">
                   <xsl:value-of select="$date_latest => year-from-date() => format-number('0000')"/>
               </j:string>  
           </xsl:if>
           <!-- i guess we'll combine the label and the unitdatetype here.  need something to distinguish between bulk dates, or just remove those? -->
           <j:string key="date_role_label">
               <!-- is Creation okay, or do i need to change this to "created" like the other examples.  Why do the exmaples have lower-cased display names? -->
                <xsl:value-of select="$date_role_label"/>
               <!-- just add to display?
               <xsl:if test="@unitdatetype eq 'bulk'">
                   <xsl:text> (bulk dates)</xsl:text>
               </xsl:if>
               -->
           </j:string>
           
           <!-- don't have the next two in ASpace, but we could map to something if that's desired -->
           <j:string key="date_role_code">
               <xsl:choose>
                   <xsl:when test="$date_role_label eq 'Created'">
                       <xsl:text>cre</xsl:text>
                   </xsl:when>
                   <xsl:otherwise/>
               </xsl:choose>
           </j:string>
               
           <!-- gotta get a list of these, as well -->
           <!-- e.g. broadcast, accession, digitizaiton, etc. -->
           <j:array key="date_role_URI">
               <j:string >
                   <xsl:choose>
                       <xsl:when test="$date_role_label eq 'Created'">
                           <xsl:text>http://vocab.getty.edu/page/aat/300435447</xsl:text>
                       </xsl:when>
                       <xsl:otherwise/>
                   </xsl:choose>
               </j:string>
           </j:array>
                     
       </j:map>
   </xsl:template>
    
    <xsl:template match="ead3:daterange" mode="#all">
        <xsl:apply-templates select="ead3:fromdate"/>
        <xsl:if test="ead3:todate">
            <xsl:text>&#x2013;</xsl:text>
        </xsl:if>
        <xsl:apply-templates select="ead3:todate"/>
    </xsl:template>

    
    <xsl:template match="ead3:*" mode="subjects">
        <j:map>
            <j:array key="subject_heading_display">
                <j:map>
                    <j:string key="value">
                        <xsl:value-of select="string-join(ead3:part/normalize-space(), '--')"/>
                    </j:string>
                </j:map>
            </j:array>
            <j:string key="subject_heading_sortname">
                <xsl:value-of select="string-join(ead3:part/normalize-space(), '--')"/>
            </j:string>
            <xsl:if test="starts-with(@identifier, 'http')">
                <j:array key="subject_heading_URI">
                    <j:string>
                        <xsl:value-of select="normalize-space(@identifier)"/>
                    </j:string>
                </j:array>
            </xsl:if>
            <j:array key="subject_facets">
                <xsl:apply-templates select="ead3:part" mode="facets"/>
            </j:array>
        </j:map>
    </xsl:template>
    
    
    <xsl:template match="ead3:part" mode="facets">
        <xsl:variable name="why-facet-type-why" select="(map:get($subject-facet-types, @localtype), @localtype)[1]"/>
        <j:map>
            <j:array key="facet_display">
                <j:map>
                    <j:string key="value">
                        <xsl:apply-templates/>
                    </j:string>
                </j:map>
            </j:array>
            <j:string key="facet_type">
                <xsl:value-of select="$why-facet-type-why"/>
            </j:string>
            <!-- oi / oy. these labels really don't belong in the metadata -->
            <j:string key="facet_type_label">
                <xsl:value-of select="concat(upper-case(substring($why-facet-type-why,1,1)),
                    substring($why-facet-type-why, 2),
                    ' '[not(last())])"/>
            </j:string>
            <!-- can't store part URIs in ASpace, but if we could, they'd show up as identifiers in EAD 
                to include now, we'd need to perform a metadata enrichment step during this ETL workflow
            <j:array key="facet_URI">
                <j:string>
                    <xsl:value-of select="normalize-space(@identifier)"/>
                </j:string>
            </j:array>
            -->
        </j:map>
    </xsl:template>


    <xsl:template name="measurements" match="ead3:physdescstructured" mode="measurements">
        <xsl:variable name="duration-extent" select="if (matches(ead3:unittype, '^duration', 'i')) then 'duration' else ()"/>
        <j:map>
            <j:string key="measurement_label">
                <xsl:value-of select="if ($duration-extent) then 'Duration' else 'Extent'"/>
            </j:string>
            <j:array key="measurement_form">
                <j:map>
                    <j:array key="measurement_display">
                        <j:map>
                            <j:string key="value">
                                <xsl:value-of select="if ($duration-extent) then mdc:convert-duration(ead3:quantity)
                                    else (ead3:quantity || ' ' || ead3:unittype) => normalize-space()"/>
                                <!-- keep an eye on descriptivenote.  it should wind up with paragraph tags, but who knows if that will break things here -->
                                <xsl:apply-templates select="ead3:physfacet  | ead3:dimensions | ead3:descriptivenote"/>
                                <!-- i should update the EAD3 exporter to put the container summary in descriptivenote.  for now, just treat it separately -->
                                <xsl:if test="following-sibling::ead3:physdesc[1][@localtype='container_summary']">
                                    <xsl:text> </xsl:text>
                                    <xsl:apply-templates select="following-sibling::ead3:physdesc[1][@localtype='container_summary']"/>
                                </xsl:if>
                            </j:string>
                        </j:map>
                    </j:array>
                    <j:array key="measurement_aspect">
                        <j:map>
                            <!-- consider different options based on unittype -->
                            <j:string key="measurement_type">
                                <xsl:value-of select="($duration-extent, 'extent')[1]"/>
                            </j:string>
                            <j:string key="measurement_value">
                                <xsl:apply-templates select="ead3:quantity"/>
                            </j:string>
                            <j:string key="measurement_unit">
                                <xsl:apply-templates select="ead3:unittype"/>
                            </j:string>
                        </j:map>
                    </j:array>
                </j:map>
            </j:array>
        </j:map>   
    </xsl:template>
    
    <xsl:template match="ead3:physdesc[@localtype='container_summary']">
        <xsl:choose>
            <!-- testing to see if it already has parantheses. if so, don't add 'em. -->
            <xsl:when test="matches(normalize-space(.), '^[(](.*)[)]$')">
                <xsl:apply-templates/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:text>(</xsl:text>
                <xsl:apply-templates/>
                <xsl:text>)</xsl:text>
            </xsl:otherwise>
        </xsl:choose>
        
    </xsl:template>
    
    <xsl:template match="ead3:physfacet">
        <xsl:choose>
            <xsl:when test="preceding-sibling::ead3:unittype">
                <xsl:text> : </xsl:text>
                <xsl:apply-templates/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:apply-templates/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>
    <xsl:template match="ead3:dimensions">
        <xsl:choose>
            <xsl:when test="preceding-sibling::ead3:unittype | preceding-sibling::ead3:physfacet">
                <xsl:text> ; </xsl:text>
                <xsl:apply-templates/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:apply-templates/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>
    
    <!-- let's lower case the Linear Feet and Linear Foot statements -->
    <xsl:template match="ead3:unittype" mode="#all">
        <xsl:text> </xsl:text>
        <xsl:choose>
            <xsl:when test="starts-with(lower-case(.), 'linear')">
                <xsl:value-of select="lower-case(.)"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:apply-templates/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>
 
    
    <!-- should we concact, or is it okay to supply a separate hash for each container group?
        doing the latter for now -->
    <xsl:template match="container-group">
        <j:map>
            <j:array key="note_display">
                <j:map>
                    <j:string key="value">
                        <xsl:apply-templates select="ead3:container"/>   
                    </j:string>
                </j:map>
            </j:array>
            <j:string key="note_type">
                <xsl:value-of select="'container'"/>
            </j:string>
            <j:string key="note_label">
                <xsl:value-of select="'Stored In'"/>
            </j:string>
        </j:map>
    </xsl:template>
    
    <xsl:template match="ead3:container">
        <xsl:value-of select="if (@localtype eq 'item_barcode') then translate(@localtype, '_', ' ') || ' ' else @localtype || ' '"/>
        <xsl:apply-templates/>
        <xsl:if test="following-sibling::*">
            <xsl:text>, </xsl:text>
        </xsl:if>
    </xsl:template>
    
    
    <!-- other named templates -->
    <xsl:template name="collections">
        <j:array key="collections">
            <j:string>
                <xsl:choose>
                    <xsl:when test="$repo-code eq 'beinecke'">
                        <xsl:value-of select="(map:get($beinecke_sub_collections, $curatorial-code), $default-general-collection-name)[1]"/>
                    </xsl:when>
                    <xsl:when test="$repo-code eq 'mssa'">
                        <xsl:value-of select="map:get($mssa_sub_collections, $curatorial-code)"/>
                    </xsl:when>
                    <!--  adding a different default for Arts, so right now it will either be VRC or SC. -->
                    <xsl:when test="$repo-code eq 'arts'">
                        <xsl:value-of select="(map:get($arts_sub_collections, $curatorial-code), 'Arts Library Special Collections')[1]"/>
                    </xsl:when>
                    <xsl:when test="$repo-code eq 'ypm'">
                        <xsl:value-of select="map:get($ypm_sub_collections, $curatorial-code)"/>
                    </xsl:when>
                    <xsl:when test="$repository-name eq 'Yale Center for British Art, Institutional Archives'">
                        <xsl:text>Institutional Archives (YCBA)</xsl:text>
                    </xsl:when>
                    <xsl:when test="$repository-name eq 'Yale Center for British Art, Rare Books and Manuscripts'">
                        <xsl:text>Rare Books and Manuscripts (YCBA)</xsl:text>
                    </xsl:when>
                    <!-- Medical:
                            "Ms" and "Pam"
                         Music:
                            "Mss" and "Misc."
                         Div:
                            "RG"
                         Arts: 
                            "VRC", "BKP", "AOB", "DRA", what else? 
                         YCBA-IA:
                            A, S
                        -->
                    <xsl:otherwise>
                        <xsl:value-of select="$default-general-collection-name"/>
                    </xsl:otherwise>
                </xsl:choose>
            </j:string>
        </j:array>
    </xsl:template>  
    

</xsl:stylesheet>
