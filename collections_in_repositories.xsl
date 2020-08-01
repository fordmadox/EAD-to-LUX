<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema"
    xmlns:math="http://www.w3.org/2005/xpath-functions/math" exclude-result-prefixes="xs math"
    version="3.0">

    <xsl:variable name="arts_sub_collections" select="map{
        'VRC': 'Visual Resources Collection'
        }"/>
    
    <xsl:variable name="beinecke_sub_collections" select="map{
        'JWJ': 'James Weldon Johnson Memorial Collection',
        'OSB': 'James Marshall and Marie-Louise Osborn Collection',
        'OSBORN': 'James Marshall and Marie-Louise Osborn Collection',
        'WA': 'Yale Collection of Western Americana',
        'YCAL': 'Yale Collection of American Literature',
        'YCGL': 'Yale Collection of German Literature',
        (: remove once beinecke.livingtheatre is finished :)
        'Multiple': 'Yale Collection of American Literature'
        }"/>
    
    <xsl:variable name="mssa_sub_collections" select="map{
        'RU': 'University Archives'
        }"/>
      
    <xsl:variable name="ypm_sub_collections" select="map{
        'ANTAR': 'Anthropology',
        'BOTAR': 'Botany',
        'ENTAR': 'Entomology',
        'IPAR': 'Invertebrate Paleontology',
        'IZAR': 'Invertebrate Zoology',
        'MINAR': 'Mineralogy &amp; Meteoritics',
        'PBAR': 'Paleobotany',
        'VPAR': 'Vertebrate Paleontology',
        'VZAR': 'Vertebrate Zoology',
        'YPMAR': 'Archives'
        }"/>
       
</xsl:stylesheet>
