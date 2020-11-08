<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:ead3="http://ead3.archivists.org/schema/"
    xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:saxon="http://saxon.sf.net/"
    xmlns:map="http://www.w3.org/2005/xpath-functions/map"
    xmlns:mdc="http://mdc"
    xmlns:h="http://www.w3.org/1999/xhtml"
    xmlns:j="http://www.w3.org/2005/xpath-functions" version="3.0">
    
    
    <!-- 
        why not just convert to HTML using templates and
        then use the serialize function?
        serialize($converted-to-html, map{'method': 'html'})
        that should work still, perhaps?
        -->
    
    <xsl:key name="id" match="ead3:*" use="@id"/>
    
    <xsl:function name="mdc:resolve-internal-link" as="xs:string">
        <!-- should update to look for notes vs. components, etc.
        Aspace only supports internal links for components, though, so just starting with that for now.-->
        <xsl:param name="target" as="node()"/>
        <xsl:variable name="prefix" select="'aspace-archival-object-'"/>
        <xsl:variable name="url" select="if ($target[@altrender]) then $target/tokenize(@altrender, '/')[last()] else ''"/>
        <xsl:value-of select="if ($url) then $prefix || $url else '#' || $target"/>
    </xsl:function>
    
    <!-- EAD stats
        
        level values:
            collection
            otherlevel
            file
            item
            series
            subseries
            subgrp   (investigate)
            recordgrp  (investigate)

        otherlevel values:
            accesssion
            accession
            Accession
            Acquisition
            Heading
            Group
            Box
            scan
        
     -->
    
    <!-- gotta be a better way, but here's a stringy start -->
    <xsl:template name="html-ify">
        <xsl:param name="element-name"/>
        <xsl:param name="preceding-text"/>
        <xsl:param name="succeeding-text"/>

        <xsl:param name="attribute-map" select="map{}" as="map(*)"/>
        <xsl:param name="nested-element"/>
        <xsl:param name="nested-attribute-map" select="map{}" as="map(*)"/>
        
        <xsl:choose>
            <xsl:when test="$nested-element">
                <xsl:value-of select="'&lt;' || $element-name || '>'"/>
                <xsl:call-template name="html-ify">
                    <xsl:with-param name="element-name" select="$nested-element"/>
                    <xsl:with-param name="attribute-map" select="$nested-attribute-map"/>
                </xsl:call-template>
                <xsl:value-of select="'&lt;/' || $element-name || '>'"/> 
            </xsl:when>
            <xsl:otherwise>
                <xsl:choose>
                    <xsl:when test="map:size($attribute-map) >= 1">
                        <xsl:value-of select="'&lt;' || $element-name || ' '"/>
                        <!-- here come the attributes -->
                        <xsl:sequence select="map:for-each($attribute-map, function ($k, $v) 
                            {  string-join(concat($k, '=''', $v, ''''), ' ') }
                            )"/>
                        <xsl:value-of select="'>'"/>
                    </xsl:when>
                    <xsl:otherwise>
                        <xsl:value-of select="'&lt;' || $element-name || '>'"/>
                    </xsl:otherwise>
                </xsl:choose>
                
                <xsl:value-of select="if ($preceding-text) then $preceding-text else ''"/>
                    <xsl:apply-templates/>
                <xsl:value-of select="if ($succeeding-text) then $succeeding-text else ''"/>
                <xsl:value-of select="'&lt;/' || $element-name || '>'"/> 
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template>
    

    
    <!-- we've got 26 bilbliographies, all with head, p, and bibref children, so that's all 
    we need to contend with, thankfully. -->

    
    <!-- we've got 199 chronlists, all with head and chronitem children -->
    <!-- chronitem:  datesingle, chronitemset -->
    <!-- chronitemset: event -->
    <!-- event: title, emph -->
    <xsl:template match="ead3:chronitem">
        <xsl:call-template name="html-ify" >
            <xsl:with-param name="element-name" select="'tr'"/>
        </xsl:call-template>
    </xsl:template>
    <xsl:template match="ead3:chronitem/ead3:datesingle | ead3:chronitem/ead3:chronitemset">
        <xsl:call-template name="html-ify" >
            <xsl:with-param name="element-name" select="'td'"/>
        </xsl:call-template>
    </xsl:template>
    <xsl:template match="ead3:chronitem/ead3:chronitemset/ead3:event[following-sibling::ead3:event]">
        <xsl:apply-templates/>
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'br'"/>
        </xsl:call-template>
    </xsl:template>
    
    
    
    <!-- remove this mapping for most notes if the type will determine a label... or just remove because it's decided they're not needed for most notes -->
    <!-- what we do here really depends on how notes display in lux.  will they have labels... or, perhaps better, will the schema be updated to accept "label" in additoin to type-->
    <xsl:template match="ead3:head">
        <!--
        <xsl:apply-templates/>
        <xsl:if test="not(ends-with(normalize-space(.), ':'))">
            <xsl:text>: </xsl:text>
        </xsl:if>
        -->
    </xsl:template>
    
    <xsl:template match="ead3:bibliography[ead3:bibref]">
        <!-- using a for-each to switch context -->
        <xsl:for-each select="ead3:head">
            <xsl:call-template name="html-ify" >
                <xsl:with-param name="element-name" select="'strong'"/>
            </xsl:call-template>
        </xsl:for-each>
        <xsl:for-each select="ead3:p">
            <xsl:call-template name="html-ify" >
                <xsl:with-param name="element-name" select="'p'"/>
            </xsl:call-template>
        </xsl:for-each>
        <xsl:call-template name="html-ify" >
            <xsl:with-param name="element-name" select="'ul'"/>
        </xsl:call-template>
    </xsl:template>
    
    <!-- use the problem of bibrefs as an example issue for EAD3/EAC recon.
        bibrefs can be list items, or they can be mixed content in other elements
        like otherfindaid.  that's a lot -->
    <xsl:template match="ead3:bibliography/ead3:bibref">
        <xsl:call-template name="html-ify" >
            <xsl:with-param name="element-name" select="'li'"/>
        </xsl:call-template>
    </xsl:template>
    <xsl:template match="ead3:bibliography/ead3:bibref[@href]" priority="2">
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'li'"/>
            <xsl:with-param name="nested-element" select="'a'"/>
            <xsl:with-param name="nested-attribute-map" select="map{'href':@href}"/>
        </xsl:call-template>
    </xsl:template>
    <!-- and for mixed-content purposes, bibref is added below, as well -->
        
    
    
    <!-- we only have on index.  how that possible? -->
    <xsl:template match="ead3:index[ead3:indexentry]">
        <!-- using a for-each to switch context -->
        <xsl:for-each select="ead3:head">
            <xsl:call-template name="html-ify" >
                <xsl:with-param name="element-name" select="'strong'"/>
            </xsl:call-template>
        </xsl:for-each>
        <xsl:for-each select="ead3:p">
            <xsl:call-template name="html-ify" >
                <xsl:with-param name="element-name" select="'p'"/>
            </xsl:call-template>
        </xsl:for-each>
        <xsl:call-template name="html-ify" >
            <xsl:with-param name="element-name" select="'dl'"/>
        </xsl:call-template>
    </xsl:template>
    
    <xsl:template match="ead3:indexentry/ead3:*[1]">
        <xsl:call-template name="html-ify" >
            <xsl:with-param name="element-name" select="'dt'"/>
        </xsl:call-template>
    </xsl:template>
    <xsl:template match="ead3:indexentry/ead3:*[2]">
        <xsl:call-template name="html-ify" >
            <xsl:with-param name="element-name" select="'dd'"/>
        </xsl:call-template>
    </xsl:template>
    <xsl:template match="ead3:indexentry/ead3:*[2][@href]" priority="2">
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'dd'"/>
            <xsl:with-param name="nested-element" select="'a'"/>
            <xsl:with-param name="nested-attribute-map" select="map{'href':@href}"/>
        </xsl:call-template>
    </xsl:template>
    <xsl:template match="ead3:indexentry/ead3:*[2][@target]" priority="3">
        <!-- @target is used as a fall-back, in case there is no matching ID attribute in the file -->
        <xsl:variable name="href-link" select="mdc:resolve-internal-link((key('id', @target), @target)[1])"/>
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'dd'"/>
            <xsl:with-param name="nested-element" select="'a'"/>
            <xsl:with-param name="nested-attribute-map" select="map{'href': $href-link}"/>
        </xsl:call-template>
    </xsl:template>
    
    <!-- could add colspec to the attribute map for table, but do we have any??? -->
    
    <!-- tables and lists, attributes:
        
cols                    177x, 5 distinct integers [1, 5], leaf
numeration              61x, 4 distinct strings, leaf
valign                  40x, 2 distinct strings, leaf
        -->
    
    
    <!-- formatting elementents -->
    <xsl:template match="ead3:p | ead3:blockquote | ead3:table | ead3:thead | ead3:tbody | ead3:abbr">
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="local-name()"/>
        </xsl:call-template>
    </xsl:template>
    <xsl:template match="ead3:abbr[@expan]" priority="2">
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="local-name()"/>
            <xsl:with-param name="nested-attribute-map" select="map{'title':@expan}"/>
        </xsl:call-template>
    </xsl:template>
    <xsl:template match="ead3:lb">
        <!-- or use this if br doesn't work
        <xsl:text>\n</xsl:text>
        -->
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'br'"/>
        </xsl:call-template>
    </xsl:template>
    <xsl:template match="ead3:emph[not(@render)]">
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'em'"/>
        </xsl:call-template>
    </xsl:template>
    
    <xsl:template match="ead3:table/ead3:head | ead3:chronlist/ead3:head">
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'caption'"/>
        </xsl:call-template>
    </xsl:template>
    
    <xsl:template match="ead3:row | ead3:thead/ead3:row 
        | ead3:listhead/head01 | ead3:listhead/head02 | ead3:listhead/head03">
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'tr'"/>
        </xsl:call-template>
    </xsl:template>
    
    <xsl:template match="ead3:thead/ead3:row/ead3:entry" priority="2">
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'th'"/>
        </xsl:call-template>
    </xsl:template>
    
    <xsl:template match="ead3:entry">
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'td'"/>
        </xsl:call-template>
    </xsl:template>
    
    <xsl:template match="ead3:chronlist">
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'table'"/>
        </xsl:call-template>
    </xsl:template>
    
    <xsl:template match="ead3:listhead">
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'thead'"/>
        </xsl:call-template>
    </xsl:template>


    
    <!-- lists, oi -->
    <xsl:template match="ead3:list[@listtype eq 'ordered']">
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'ol'"/>
        </xsl:call-template>
    </xsl:template>
    <xsl:template match="ead3:list[@listtype eq 'unordered']">
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'ul'"/>
        </xsl:call-template>
    </xsl:template>
    <xsl:template match="ead3:list[@listtype eq 'deflist']">
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'dl'"/>
        </xsl:call-template>
    </xsl:template>
    
    <xsl:template match="ead3:item">
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'li'"/>
        </xsl:call-template>
    </xsl:template>
    
    <xsl:template match="ead3:defitem/ead3:label">
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'dt'"/>
        </xsl:call-template>
    </xsl:template>
    <xsl:template match="ead3:defitem/ead3:item">
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'dd'"/>
        </xsl:call-template>
    </xsl:template>

    
   
    <xsl:template match="ead3:title[not(@render)]">
        <xsl:if test="preceding-sibling::* | preceding-sibling::text()"> <xsl:text> </xsl:text></xsl:if>
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'em'"/>
        </xsl:call-template>
    </xsl:template>
    
    
    <!-- this group borrowed from W.S.'s ASpace stylesheet -->
    <xsl:template match="*[@render = 'bold'] | *[@altrender = 'bold'] ">
        <xsl:if test="preceding-sibling::* | preceding-sibling::text()"> <xsl:text> </xsl:text></xsl:if>
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'strong'"/>
        </xsl:call-template>
    </xsl:template>
    
    <xsl:template match="*[@render = 'bolddoublequote'] | *[@altrender = 'bolddoublequote']">
        <xsl:if test="preceding-sibling::* | preceding-sibling::text()"> <xsl:text> </xsl:text></xsl:if>
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'strong'"/>
            <xsl:with-param name="preceding-text">"</xsl:with-param>
            <xsl:with-param name="succeeding-text">"</xsl:with-param>
        </xsl:call-template>
        
    </xsl:template>
    
    <xsl:template match="*[@render = 'boldsinglequote'] | *[@altrender = 'boldsinglequote']">
        <xsl:if test="preceding-sibling::* | preceding-sibling::text()"> <xsl:text> </xsl:text></xsl:if>
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'strong'"/>
            <xsl:with-param name="preceding-text">'</xsl:with-param>
            <xsl:with-param name="succeeding-text">'</xsl:with-param>
        </xsl:call-template>
    </xsl:template>
    
    <xsl:template match="*[@render = 'bolditalic'] | *[@altrender = 'bolditalic']">
        <xsl:if test="preceding-sibling::* | preceding-sibling::text()"> <xsl:text> </xsl:text></xsl:if>
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'strong'"/>
            <xsl:with-param name="nested-element" select="'em'"/>
        </xsl:call-template>
    </xsl:template>
    
    <xsl:template match="*[@render = 'boldsmcaps'] | *[@altrender = 'boldsmcaps']">
        <xsl:if test="preceding-sibling::* | preceding-sibling::text()"> <xsl:text> </xsl:text></xsl:if>
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'strong'"/>
            <xsl:with-param name="nested-element" select="'span'"/>
            <xsl:with-param name="nested-attribute-map" select="map{'class':'smcaps'}"/>
        </xsl:call-template>
    </xsl:template>
    
    <xsl:template match="*[@render = 'boldunderline'] | *[@altrender = 'boldunderline']">
        <xsl:if test="preceding-sibling::* | preceding-sibling::text()"> <xsl:text> </xsl:text></xsl:if>
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'strong'"/>
            <xsl:with-param name="nested-element" select="'span'"/>
            <xsl:with-param name="nested-attribute-map" select="map{'class':'underline'}"/>
        </xsl:call-template>
    </xsl:template>
    
    <xsl:template match="*[@render = 'doublequote'] | *[@altrender = 'doublequote']">
        <xsl:if test="preceding-sibling::* | preceding-sibling::text()"> <xsl:text> </xsl:text></xsl:if>
        "<xsl:apply-templates/>"
    </xsl:template>
    
    <xsl:template match="*[@render = 'italic'] | *[@altrender = 'italic']">
        <xsl:if test="preceding-sibling::* | preceding-sibling::text()"> <xsl:text> </xsl:text></xsl:if>
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'em'"/>
        </xsl:call-template>
    </xsl:template>
    
    <xsl:template match="*[@render = 'singlequote'] | *[@altrender = 'singlequote']">
        <xsl:if test="preceding-sibling::* | preceding-sibling::text()"> <xsl:text> </xsl:text></xsl:if>
        '<xsl:apply-templates/>'
    </xsl:template>
    
    <xsl:template match="*[@render = 'smcaps'] | *[@altrender = 'smcaps']">
        <xsl:if test="preceding-sibling::* | preceding-sibling::text()"> <xsl:text> </xsl:text></xsl:if>
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'span'"/>
            <xsl:with-param name="attribute-map" select="map{'class':'smcaps'}"/>
        </xsl:call-template>
    </xsl:template>
    
    <xsl:template match="*[@render = 'sub'] | *[@altrender = 'sub']">
        <xsl:if test="preceding-sibling::* | preceding-sibling::text()"> <xsl:text> </xsl:text></xsl:if>
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'sub'"/>
        </xsl:call-template>
    </xsl:template>
    
    <xsl:template match="*[@render = 'super'] | *[@altrender = 'super']">
        <xsl:if test="preceding-sibling::* | preceding-sibling::text()"> <xsl:text> </xsl:text></xsl:if>
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'sup'"/>
        </xsl:call-template>
    </xsl:template>
    
    <xsl:template match="*[@render = 'underline'] | *[@altrender = 'underline']">
        <xsl:if test="preceding-sibling::* | preceding-sibling::text()"> <xsl:text> </xsl:text></xsl:if>
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'span'"/>
            <xsl:with-param name="attribute-map" select="map{'class':'underline'}"/>
        </xsl:call-template>
    </xsl:template>
    
    
    


    

    
    <!-- Linking elmenets.  TEST!.  also, what other attributes... and should we use a map merge here, i guess. -->
    <xsl:template match="ead3:ref[@href] | ead3:bibref[@href]">
        <xsl:call-template name="html-ify">
            <xsl:with-param name="element-name" select="'a'"/>
            <xsl:with-param name="attribute-map" select="if (@linktitle) 
                then map{'href': @href, 'title': @linktitle}
                else map{'href': @href}
                "/>
        </xsl:call-template>
    </xsl:template>
    <xsl:template match="ead3:ptr[@target] | ead3:ref[@target]">
        <!-- @target is used as a fall-back, in case there is no matching ID attribute in the file -->
        <xsl:variable name="href-link" select="mdc:resolve-internal-link((key('id', @target), @target)[1])"/>
            <xsl:call-template name="html-ify">
                <xsl:with-param name="element-name" select="'a'"/>
                <xsl:with-param name="attribute-map" select="if (@linktitle) 
                    then map{'href': $href-link, 'title': @linktitle}
                    else map{'href': $href-link}
                    "/>
            </xsl:call-template>
    </xsl:template>
    
    <!-- access rights note stuff, as borrowed from PDF examples -->
    <xsl:template name="access_notes">
        <xsl:param name="repo-code"/>
        <xsl:param name="collection-URI"/>
        <xsl:choose>
            <!-- update once you know what to put here -->
            <xsl:when test="$repo-code eq 'ypm'"/>
            <xsl:when test="$repo-code eq 'beinecke'">
                <xsl:text>&lt;p>To request items from this collection for use in the Beinecke Library reading room, please use the request links in the HTML version of this finding aid, available at </xsl:text>
                <xsl:text expand-text="true">&lt;a href='{$collection-URI}'>{$collection-URI}&lt;/a></xsl:text>
                <xsl:text>.&lt;/p>&lt;p>To order reproductions from this collection, please send an email with the call number, box number(s), and folder number(s) to </xsl:text>
                <xsl:text>&lt;a href='mailto:beinecke.images@yale.edu'>beinecke.images@yale.edu&lt;/a>.&lt;/p></xsl:text> 
            </xsl:when>
            <xsl:when test="$repo-code eq 'mssa'">
                <xsl:text>&lt;p>To request items from this collection for use in  the Manuscripts and Archives reading room, please use the  request links in the HTML version of this finding aid, available at </xsl:text>
                <xsl:text expand-text="true">&lt;a href='{$collection-URI}'>{$collection-URI}&lt;/a></xsl:text>
                <xsl:text>.&lt;/p>&lt;p>To order reproductions from this collection, please go to </xsl:text>
                <xsl:text>&lt;a href='http://www.library.yale.edu/mssa/ifr_copy_order.html'>http://www.library.yale.edu/mssa/ifr_copy_order.html&lt;/a></xsl:text>
                <xsl:text>. The information you will need to submit an order includes: the collection call number, collection title, series or accession number, box number, and folder number or name.&lt;/p></xsl:text>
            </xsl:when>
            <xsl:otherwise>
                <xsl:text>&lt;p>To request items from this collection for use on site, please use the request links in the HTML version of this finding aid, available at </xsl:text>
                <xsl:text expand-text="true">&lt;a href='{$collection-URI}'>{$collection-URI}&lt;/a></xsl:text>
                <xsl:text>.&lt;/p></xsl:text>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:template> 
    
</xsl:stylesheet>
