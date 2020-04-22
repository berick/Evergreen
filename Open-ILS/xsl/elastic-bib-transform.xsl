<xsl:stylesheet
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:marc="http://www.loc.gov/MARC21/slim"
  version="1.0">
  <xsl:output encoding="UTF-8" method="text"/>

  <!--
      Prints one index value per line for data found by transforming
      a MARCXML record.

      Output:

      $index_purpose $index_class $index_name $value

      - $value is the only string in the output that may contain spaces.

      e.g.

      search subject topic South America
      facet author personal Janey Jam "Jojo" Jones
  -->

  <xsl:template match="@*|node()">
    <xsl:call-template name="compile_searches" />
    <xsl:call-template name="compile_facets" />
    <xsl:call-template name="compile_filters" />
    <xsl:call-template name="compile_sorters" />
    <xsl:call-template name="compile_headings" />
    <xsl:call-template name="compile_marc" />
  </xsl:template>

  <xsl:template name="compile_searches">
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">650</xsl:with-param>
      <xsl:with-param name="field_class">subject</xsl:with-param>
      <xsl:with-param name="index_name">topic</xsl:with-param>
      <xsl:with-param name="index_subfields">abcdvxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">651</xsl:with-param>
      <xsl:with-param name="field_class">subject</xsl:with-param>
      <xsl:with-param name="index_name">geographic</xsl:with-param>
      <xsl:with-param name="index_subfields">avxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">655</xsl:with-param>
      <xsl:with-param name="field_class">subject</xsl:with-param>
      <xsl:with-param name="index_name">genre</xsl:with-param>
      <xsl:with-param name="index_subfields">abcvxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">630</xsl:with-param>
      <xsl:with-param name="field_class">subject</xsl:with-param>
      <xsl:with-param name="index_name">uniftitle</xsl:with-param>
      <xsl:with-param name="index_subfields">adfgklmnoprstvxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">600</xsl:with-param>
      <xsl:with-param name="field_class">subject</xsl:with-param>
      <xsl:with-param name="index_name">name</xsl:with-param>
      <xsl:with-param name="index_subfields">abcdfgjklmnopqrstuvxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">610</xsl:with-param>
      <xsl:with-param name="field_class">subject</xsl:with-param>
      <xsl:with-param name="index_name">corpname</xsl:with-param>
      <xsl:with-param name="index_subfields">abcdfgklmnoprstuvxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">611</xsl:with-param>
      <xsl:with-param name="field_class">subject</xsl:with-param>
      <xsl:with-param name="index_name">meeting</xsl:with-param>
      <xsl:with-param name="index_subfields">acdefgjklnpqstuvxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">490</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="index_subfields">a</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">800</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="index_subfields">tflmnoprs</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">810</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="index_subfields">tflmnoprs</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">830</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="index_subfields">adfgklmnoprst</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">100</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">personal</xsl:with-param>
      <xsl:with-param name="index_subfields">abcdq</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">110</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">corporate</xsl:with-param>
      <xsl:with-param name="index_subfields">abcdn</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">111</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">meeting</xsl:with-param>
      <xsl:with-param name="index_subfields">acdegng</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">700</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">added_personal</xsl:with-param>
      <xsl:with-param name="index_subfields">abcdq</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">710</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">corporate</xsl:with-param>
      <xsl:with-param name="index_subfields">ab</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">711</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">meeting</xsl:with-param>
      <xsl:with-param name="index_subfields">acde</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">400</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">added_personal</xsl:with-param>
      <xsl:with-param name="index_subfields">abcd</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">410</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">corporate</xsl:with-param>
      <xsl:with-param name="index_subfields">abcd</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">411</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">meeting</xsl:with-param>
      <xsl:with-param name="index_subfields">acdegq</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">010</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">lccn</xsl:with-param>
      <xsl:with-param name="index_subfields">a</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">010</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">lccn</xsl:with-param>
      <xsl:with-param name="index_subfields">z</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">020</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">isbn</xsl:with-param>
      <xsl:with-param name="index_subfields">a</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">020</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">isbn</xsl:with-param>
      <xsl:with-param name="index_subfields">z</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">022</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">issn</xsl:with-param>
      <xsl:with-param name="index_subfields">a</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">022</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">issn</xsl:with-param>
      <xsl:with-param name="index_subfields">y</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">022</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">issn</xsl:with-param>
      <xsl:with-param name="index_subfields">z</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">024</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">upc</xsl:with-param>
      <xsl:with-param name="index_subfields">a</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">024</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">upc</xsl:with-param>
      <xsl:with-param name="index_subfields">z</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">027</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">tech_number</xsl:with-param>
      <xsl:with-param name="index_subfields">a</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">027</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">tech_number</xsl:with-param>
      <xsl:with-param name="index_subfields">z</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">028</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">tech_number</xsl:with-param>
      <xsl:with-param name="index_subfields">ab</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">074</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">sudoc</xsl:with-param>
      <xsl:with-param name="index_subfields">a</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">074</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">sudoc</xsl:with-param>
      <xsl:with-param name="index_subfields">z</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">086</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">sudoc</xsl:with-param>
      <xsl:with-param name="index_subfields">a</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">086</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">sudoc</xsl:with-param>
      <xsl:with-param name="index_subfields">z</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">092</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">bibcn</xsl:with-param>
      <xsl:with-param name="index_subfields">ab</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">099</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">bibcn</xsl:with-param>
      <xsl:with-param name="index_subfields">a</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">099</xsl:with-param>
      <xsl:with-param name="field_class">identifier</xsl:with-param>
      <xsl:with-param name="index_name">bibcn</xsl:with-param>
      <xsl:with-param name="index_subfields">a</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">130</xsl:with-param>
      <xsl:with-param name="field_class">title</xsl:with-param>
      <xsl:with-param name="index_name">uniform</xsl:with-param>
      <xsl:with-param name="index_subfields">abcefgijklmnopqrstuvwxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">210</xsl:with-param>
      <xsl:with-param name="field_class">title</xsl:with-param>
      <xsl:with-param name="index_name">abbreviated</xsl:with-param>
      <xsl:with-param name="index_subfields">abcefghijklmnopqrstuvwxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">222</xsl:with-param>
      <xsl:with-param name="field_class">title</xsl:with-param>
      <xsl:with-param name="index_name">magazine</xsl:with-param>
      <xsl:with-param name="index_subfields">a</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">240</xsl:with-param>
      <xsl:with-param name="field_class">title</xsl:with-param>
      <xsl:with-param name="index_name">uniform</xsl:with-param>
      <xsl:with-param name="index_subfields">abcefgijklmnopqrstuvwxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">245</xsl:with-param>
      <xsl:with-param name="field_class">title</xsl:with-param>
      <xsl:with-param name="index_name">maintitle</xsl:with-param>
      <xsl:with-param name="index_subfields">a</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">245</xsl:with-param>
      <xsl:with-param name="field_class">title</xsl:with-param>
      <xsl:with-param name="index_name">proper</xsl:with-param>
      <xsl:with-param name="index_subfields">abefgijklmnopqrstuvwxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">245</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">responsibility</xsl:with-param>
      <xsl:with-param name="index_subfields">c</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">246</xsl:with-param>
      <xsl:with-param name="field_class">title</xsl:with-param>
      <xsl:with-param name="index_name">alternative</xsl:with-param>
      <xsl:with-param name="index_subfields">abcefgjklmnopqrstuvwxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">247</xsl:with-param>
      <xsl:with-param name="field_class">title</xsl:with-param>
      <xsl:with-param name="index_name">former</xsl:with-param>
      <xsl:with-param name="index_subfields">abcefgijklmnopqrstuvwxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">260</xsl:with-param>
      <xsl:with-param name="field_class">keyword</xsl:with-param>
      <xsl:with-param name="index_name">publisher</xsl:with-param>
      <xsl:with-param name="index_subfields">b</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">264</xsl:with-param>
      <xsl:with-param name="field_class">keyword</xsl:with-param>
      <xsl:with-param name="index_name">publisher</xsl:with-param>
      <xsl:with-param name="index_subfields">b</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">245</xsl:with-param>
      <xsl:with-param name="field_class">keyword</xsl:with-param>
      <xsl:with-param name="index_name">title</xsl:with-param>
      <xsl:with-param name="index_subfields">a</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">100</xsl:with-param>
      <xsl:with-param name="field_class">keyword</xsl:with-param>
      <xsl:with-param name="index_name">author</xsl:with-param>
      <xsl:with-param name="index_subfields">abcdq</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">400</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="index_subfields">ptv</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">410</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">corporate</xsl:with-param>
      <xsl:with-param name="index_subfields">abcde</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">410</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="index_subfields">ptv</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">411</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">conference</xsl:with-param>
      <xsl:with-param name="index_subfields">acdegq</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">411</xsl:with-param>
      <xsl:with-param name="field_class">title</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="index_subfields">ptv</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">440</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="index_subfields">abcefghijklmnopqrstuvwyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">490</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="index_subfields">abcefghijklmnopqrstuvwyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">490</xsl:with-param>
      <xsl:with-param name="field_class">title</xsl:with-param>
      <xsl:with-param name="index_name">uniform</xsl:with-param>
      <xsl:with-param name="index_subfields">abcefghijklmnopqrstuvwyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">694</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="index_subfields">a</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">700</xsl:with-param>
      <xsl:with-param name="field_class">title</xsl:with-param>
      <xsl:with-param name="index_name">added</xsl:with-param>
      <xsl:with-param name="index_subfields">fgklmnoprst</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">710</xsl:with-param>
      <xsl:with-param name="field_class">title</xsl:with-param>
      <xsl:with-param name="index_name">added</xsl:with-param>
      <xsl:with-param name="index_subfields">fgklmnoprst</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">711</xsl:with-param>
      <xsl:with-param name="field_class">title</xsl:with-param>
      <xsl:with-param name="index_name">added</xsl:with-param>
      <xsl:with-param name="index_subfields">fklnpst</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">730</xsl:with-param>
      <xsl:with-param name="field_class">title</xsl:with-param>
      <xsl:with-param name="index_name">added</xsl:with-param>
      <xsl:with-param name="index_subfields">abcefgijklmnopqrstuvwyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">740</xsl:with-param>
      <xsl:with-param name="field_class">title</xsl:with-param>
      <xsl:with-param name="index_name">added</xsl:with-param>
      <xsl:with-param name="index_subfields">abcefgijklmnopqrstuvwyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">780</xsl:with-param>
      <xsl:with-param name="field_class">title</xsl:with-param>
      <xsl:with-param name="index_name">previous</xsl:with-param>
      <xsl:with-param name="index_subfields">st</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">785</xsl:with-param>
      <xsl:with-param name="field_class">title</xsl:with-param>
      <xsl:with-param name="index_name">succeeding</xsl:with-param>
      <xsl:with-param name="index_subfields">st</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">800</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">personal_series</xsl:with-param>
      <xsl:with-param name="index_subfields">abcdq</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">800</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="index_subfields">fgklmnoprst</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">810</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">corporate_series</xsl:with-param>
      <xsl:with-param name="index_subfields">abcdn</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">810</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="index_subfields">abcdn</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">811</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">conference_series</xsl:with-param>
      <xsl:with-param name="index_subfields">acdegnq</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">811</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="index_subfields">fklnpstv</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_search_entry">
      <xsl:with-param name="tag">830</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="index_subfields">abcefgijklmnopqrstuvwxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="keyword_full_entry" />
  </xsl:template>

  <xsl:template name="compile_facets">
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">650</xsl:with-param>
      <xsl:with-param name="field_class">subject</xsl:with-param>
      <xsl:with-param name="index_name">topic</xsl:with-param>
      <xsl:with-param name="facet_subfields">abcdvxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">651</xsl:with-param>
      <xsl:with-param name="field_class">subject</xsl:with-param>
      <xsl:with-param name="index_name">geographic</xsl:with-param>
      <xsl:with-param name="facet_subfields">avxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">600</xsl:with-param>
      <xsl:with-param name="field_class">subject</xsl:with-param>
      <xsl:with-param name="index_name">name</xsl:with-param>
      <xsl:with-param name="facet_subfields">abcdfgjklmnopqrstuvxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">490</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="facet_subfields">a</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">800</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="facet_subfields">tflmnoprs</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">810</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="facet_subfields">tflmnoprs</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">830</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="facet_subfields">adfgklmnoprst</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">100</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">personal</xsl:with-param>
      <xsl:with-param name="facet_subfields">abcdq</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">110</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">corporate</xsl:with-param>
      <xsl:with-param name="facet_subfields">ab</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">710</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">corporate</xsl:with-param>
      <xsl:with-param name="facet_subfields">ab</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">410</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">corporate</xsl:with-param>
      <xsl:with-param name="facet_subfields">abcd</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">400</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="facet_subfields"></xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">410</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">corporate</xsl:with-param>
      <xsl:with-param name="facet_subfields"></xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">410</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="facet_subfields"></xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">411</xsl:with-param>
      <xsl:with-param name="field_class">author</xsl:with-param>
      <xsl:with-param name="index_name">conference</xsl:with-param>
      <xsl:with-param name="facet_subfields"></xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">411</xsl:with-param>
      <xsl:with-param name="field_class">title</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="facet_subfields"></xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">440</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="facet_subfields">abcefghijklmnopqrstuvwyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">490</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="facet_subfields"></xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">694</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="facet_subfields"></xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">800</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="facet_subfields">fgklmnoprst</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">810</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="facet_subfields">abcdn</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">811</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="facet_subfields">fklnpstv</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_facet_entry">
      <xsl:with-param name="tag">830</xsl:with-param>
      <xsl:with-param name="field_class">series</xsl:with-param>
      <xsl:with-param name="index_name">seriestitle</xsl:with-param>
      <xsl:with-param name="facet_subfields">abcefgijklmnopqrstuvwxyz</xsl:with-param>
    </xsl:call-template>
  </xsl:template>

  <xsl:template name="compile_headings">
    <xsl:call-template name="add_heading_entry">
      <xsl:with-param name="tag">650</xsl:with-param>
      <xsl:with-param name="field_class">subject</xsl:with-param>
      <xsl:with-param name="index_subfields">abcdvxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_heading_entry">
      <xsl:with-param name="tag">651</xsl:with-param>
      <xsl:with-param name="field_class">subject</xsl:with-param>
      <xsl:with-param name="index_subfields">avxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_heading_entry">
      <xsl:with-param name="tag">655</xsl:with-param>
      <xsl:with-param name="field_class">subject</xsl:with-param>
      <xsl:with-param name="index_subfields">abcvxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_heading_entry">
      <xsl:with-param name="tag">630</xsl:with-param>
      <xsl:with-param name="field_class">subject</xsl:with-param>
      <xsl:with-param name="index_subfields">adfgklmnoprstvxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_heading_entry">
      <xsl:with-param name="tag">600</xsl:with-param>
      <xsl:with-param name="field_class">subject</xsl:with-param>
      <xsl:with-param name="index_subfields">abcdfgjklmnopqrstuvxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_heading_entry">
      <xsl:with-param name="tag">610</xsl:with-param>
      <xsl:with-param name="field_class">subject</xsl:with-param>
      <xsl:with-param name="index_subfields">abcdfgklmnoprstuvxyz</xsl:with-param>
    </xsl:call-template>
    <xsl:call-template name="add_heading_entry">
      <xsl:with-param name="tag">611</xsl:with-param>
      <xsl:with-param name="field_class">subject</xsl:with-param>
      <xsl:with-param name="index_subfields">acdefgjklnpqstuvxyz</xsl:with-param>
    </xsl:call-template>
  </xsl:template>

  <xsl:template name="compile_sorters">

    <!-- author sort is the first 1XX value -->
    <xsl:for-each select="marc:datafield[starts-with(@tag, '1')]">
      <xsl:sort select="@tag"/>
      <xsl:if test="position() = 1">
        <xsl:call-template name="add_sorter_entry">
          <xsl:with-param name="name">authorsort</xsl:with-param>
          <xsl:with-param name="value">
            <xsl:call-template name="subfieldSelect"></xsl:call-template>
          </xsl:with-param>
        </xsl:call-template>
      </xsl:if>
    </xsl:for-each>

    <!-- title sort is the 245a non-filing -->
    <xsl:for-each select="marc:datafield[@tag='245']">
      <xsl:variable name="full_title">
        <xsl:call-template name="subfieldSelect">
          <xsl:with-param name="codes">a</xsl:with-param>
        </xsl:call-template>
      </xsl:variable>
      <xsl:variable name="offset">
        <xsl:choose>
          <xsl:when test="number(@ind2) = @ind2">
            <xsl:value-of select="@ind2" />
          </xsl:when>
          <xsl:otherwise>
            <xsl:text>0</xsl:text>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:variable>
      <xsl:call-template name="add_sorter_entry">
        <xsl:with-param name="name">titlesort</xsl:with-param>
        <xsl:with-param name="value" select="substring($full_title, $offset + 1)" />
      </xsl:call-template>
    </xsl:for-each>

    <!-- pubdate is the same as the date1 filter -->
    <xsl:call-template name="add_sorter_entry">
      <xsl:with-param name="name">pubdate</xsl:with-param>
      <xsl:with-param name="value">
        <xsl:call-template name="controlfield_value">
          <xsl:with-param name="tag">008</xsl:with-param>
          <xsl:with-param name="offset">7</xsl:with-param>
          <xsl:with-param name="length">4</xsl:with-param>
        </xsl:call-template>
      </xsl:with-param>
    </xsl:call-template>

  </xsl:template>

  <xsl:template name="compile_filters">

    <!-- start with filters that are not used within composite filters.
         These can be added to the document inline. -->
    <xsl:call-template name="add_filter_entry">
      <xsl:with-param name="name">date1</xsl:with-param>
      <xsl:with-param name="value">
        <xsl:call-template name="controlfield_value">
          <xsl:with-param name="tag">008</xsl:with-param>
          <xsl:with-param name="offset">7</xsl:with-param>
          <xsl:with-param name="length">4</xsl:with-param>
        </xsl:call-template>
      </xsl:with-param>
      <xsl:with-param name="default_value">0000</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_filter_entry">
      <xsl:with-param name="name">date2</xsl:with-param>
      <xsl:with-param name="value">
        <xsl:call-template name="controlfield_value">
          <xsl:with-param name="tag">008</xsl:with-param>
          <xsl:with-param name="offset">11</xsl:with-param>
          <xsl:with-param name="length">4</xsl:with-param>
        </xsl:call-template>
      </xsl:with-param>
      <xsl:with-param name="default_value">9999</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_filter_entry">
      <xsl:with-param name="name">lit_form</xsl:with-param>
      <xsl:with-param name="value">
        <xsl:call-template name="controlfield_value">
          <xsl:with-param name="tag">008</xsl:with-param>
          <xsl:with-param name="offset">33</xsl:with-param>
          <xsl:with-param name="length">1</xsl:with-param>
        </xsl:call-template>
      </xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_filter_entry">
      <xsl:with-param name="name">item_lang</xsl:with-param>
      <xsl:with-param name="value">
        <xsl:call-template name="controlfield_value">
          <xsl:with-param name="tag">008</xsl:with-param>
          <xsl:with-param name="offset">35</xsl:with-param>
          <xsl:with-param name="length">3</xsl:with-param>
        </xsl:call-template>
      </xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_filter_entry">
      <xsl:with-param name="name">audience</xsl:with-param>
      <xsl:with-param name="value">
        <xsl:call-template name="controlfield_value">
          <xsl:with-param name="tag">008</xsl:with-param>
          <xsl:with-param name="offset">22</xsl:with-param>
          <xsl:with-param name="length">1</xsl:with-param>
        </xsl:call-template>
      </xsl:with-param>
    </xsl:call-template>

    <!-- Filters that may be used within composite filters are
         stored in a local variable so they can first be added
         to the document, then used to compile composite filters -->

    <xsl:variable name="item_type">
      <xsl:call-template name="leader_value">
        <xsl:with-param name="offset">6</xsl:with-param>
        <xsl:with-param name="length">1</xsl:with-param>
      </xsl:call-template>
    </xsl:variable>

    <xsl:call-template name="add_filter_entry">
      <xsl:with-param name="name">item_type</xsl:with-param>
      <xsl:with-param name="value" select="$item_type" />
    </xsl:call-template>

    <xsl:variable name="bib_level">
      <xsl:call-template name="leader_value">
        <xsl:with-param name="offset">7</xsl:with-param>
        <xsl:with-param name="length">1</xsl:with-param>
      </xsl:call-template>
    </xsl:variable>

    <xsl:call-template name="add_filter_entry">
      <xsl:with-param name="name">bib_level</xsl:with-param>
      <xsl:with-param name="value" select="$bib_level" />
    </xsl:call-template>

    <xsl:variable name="item_form">
      <xsl:call-template name="controlfield_value">
        <xsl:with-param name="tag">008</xsl:with-param>
        <xsl:with-param name="offset">23</xsl:with-param>
        <xsl:with-param name="length">1</xsl:with-param>
      </xsl:call-template>
    </xsl:variable>

    <xsl:call-template name="add_filter_entry">
      <xsl:with-param name="name">item_form</xsl:with-param>
      <xsl:with-param name="value" select="$item_form" />
    </xsl:call-template>

    <xsl:variable name="category_of_material">
      <xsl:call-template name="controlfield_value">
        <xsl:with-param name="tag">007</xsl:with-param>
        <xsl:with-param name="offset">0</xsl:with-param>
        <xsl:with-param name="length">1</xsl:with-param>
      </xsl:call-template>
    </xsl:variable>

    <xsl:variable name="vr_format">
      <xsl:if test="$category_of_material = 'v'">
        <xsl:call-template name="controlfield_value">
          <xsl:with-param name="tag">007</xsl:with-param>
          <xsl:with-param name="offset">4</xsl:with-param>
          <xsl:with-param name="length">1</xsl:with-param>
        </xsl:call-template>
      </xsl:if>
    </xsl:variable>

    <xsl:call-template name="add_filter_entry">
      <xsl:with-param name="name">vr_format</xsl:with-param>
      <xsl:with-param name="value" select="$vr_format" />
    </xsl:call-template>

    <xsl:variable name="sr_format">
      <xsl:if test="$category_of_material = 's'">
        <xsl:call-template name="controlfield_value">
          <xsl:with-param name="tag">007</xsl:with-param>
          <xsl:with-param name="offset">3</xsl:with-param>
          <xsl:with-param name="length">1</xsl:with-param>
        </xsl:call-template>
      </xsl:if>
    </xsl:variable>

    <xsl:call-template name="add_filter_entry">
      <xsl:with-param name="name">sr_format</xsl:with-param>
      <xsl:with-param name="value" select="$sr_format" />
    </xsl:call-template>

    <!-- use the extracted raw filters to create composite filters -->

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">blu-ray</xsl:with-param>
      <xsl:with-param name="vr_format" select="$vr_format" />
      <xsl:with-param name="vr_format_codes">s</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">book</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">at</xsl:with-param>
      <xsl:with-param name="item_form" select="$item_type" />
      <xsl:with-param name="item_form_not_codes">abcfoqrs</xsl:with-param>
      <xsl:with-param name="bib_level" select="$bib_level" />
      <xsl:with-param name="bib_level_codes">acdm</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">braille</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">a</xsl:with-param>
      <xsl:with-param name="item_form" select="$item_form" />
      <xsl:with-param name="item_form_codes">f</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">casaudiobook</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">i</xsl:with-param>
      <xsl:with-param name="sr_format" select="$sr_format" />
      <xsl:with-param name="sr_format_codes">l</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">casmusic</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">j</xsl:with-param>
      <xsl:with-param name="sr_format" select="$sr_format" />
      <xsl:with-param name="sr_format_codes">l</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">cdaudiobook</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">i</xsl:with-param>
      <xsl:with-param name="sr_format" select="$sr_format" />
      <xsl:with-param name="sr_format_codes">f</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">cdaudiobook</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">j</xsl:with-param>
      <xsl:with-param name="sr_format" select="$sr_format" />
      <xsl:with-param name="sr_format_codes">f</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">dvd</xsl:with-param>
      <xsl:with-param name="vr_format" select="$vr_format" />
      <xsl:with-param name="vr_format_codes">v</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">eaudio</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">i</xsl:with-param>
      <xsl:with-param name="item_form" select="$item_form" />
      <xsl:with-param name="item_form_codes">oqs</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">ebook</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">at</xsl:with-param>
      <xsl:with-param name="item_form" select="$item_form" />
      <xsl:with-param name="item_form_codes">oqs</xsl:with-param>
      <xsl:with-param name="bib_level" select="$bib_level" />
      <xsl:with-param name="bib_level_codes">acdm</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">electronic</xsl:with-param>
      <xsl:with-param name="item_form" select="$item_form" />
      <xsl:with-param name="item_form_codes">os</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">equip</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">r</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">evideo</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">g</xsl:with-param>
      <xsl:with-param name="item_form" select="$item_form" />
      <xsl:with-param name="item_form_codes">oqs</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">kit</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">op</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">lpbook</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">at</xsl:with-param>
      <xsl:with-param name="item_form" select="$item_form" />
      <xsl:with-param name="item_form_codes">d</xsl:with-param>
      <xsl:with-param name="bib_level" select="$bib_level" />
      <xsl:with-param name="bib_level_codes">acdm</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">map</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">ef</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">microform</xsl:with-param>
      <xsl:with-param name="item_form" select="$item_form" />
      <xsl:with-param name="item_form_codes">abc</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">music</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">j</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">phonomusic</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">j</xsl:with-param>
      <xsl:with-param name="sr_format" select="$sr_format" />
      <xsl:with-param name="sr_format_codes">abcde</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">phonospoken</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">i</xsl:with-param>
      <xsl:with-param name="sr_format" select="$sr_format" />
      <xsl:with-param name="sr_format_codes">abcde</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">picture</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">k</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">serial</xsl:with-param>
      <xsl:with-param name="bib_level" select="$bib_level" />
      <xsl:with-param name="bib_level_codes">bs</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">score</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">cd</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">software</xsl:with-param>
      <xsl:with-param name="item_type" select="$item_type" />
      <xsl:with-param name="item_type_codes">m</xsl:with-param>
    </xsl:call-template>

    <xsl:call-template name="add_composite_filter_entry">
      <xsl:with-param name="name">search_format</xsl:with-param>
      <xsl:with-param name="value">vhs</xsl:with-param>
      <xsl:with-param name="vr_format" select="$vr_format" />
      <xsl:with-param name="vr_format_codes">b</xsl:with-param>
    </xsl:call-template>

  </xsl:template>

  <xsl:template name="add_sorter_entry">
    <xsl:param name="name"/>
    <xsl:param name="value"/>
    <xsl:text>sorter _ </xsl:text>
    <xsl:value-of select="$name" />
    <xsl:text> </xsl:text>
    <xsl:value-of select="$value" />
    <xsl:text>&#xa;</xsl:text>
  </xsl:template>

  <xsl:template name="add_filter_entry">
    <xsl:param name="name"/>
    <xsl:param name="value"/>
    <xsl:param name="default_value"/>
    <xsl:text>filter _ </xsl:text>
    <xsl:value-of select="$name" />
    <xsl:text> </xsl:text>
    <xsl:choose>
      <xsl:when test="$default_value and translate($value, ' ', '') = ''">
        <xsl:value-of select="$default_value" />
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="$value" />
      </xsl:otherwise>
    </xsl:choose>
    <xsl:text>&#xa;</xsl:text>
  </xsl:template>

  <xsl:template name="add_composite_filter_entry">
    <xsl:param name="name"/>
    <xsl:param name="value"/>
    <xsl:param name="item_type"/>
    <xsl:param name="item_type_codes"/>
    <xsl:param name="item_form"/>
    <xsl:param name="item_form_codes"/>
    <xsl:param name="item_form_not_codes"/>
    <xsl:param name="bib_level"/>
    <xsl:param name="bib_level_codes"/>
    <xsl:param name="vr_format"/>
    <xsl:param name="vr_format_codes"/>
    <xsl:param name="sr_format"/>
    <xsl:param name="sr_format_codes"/>

    <xsl:variable name="item_type_matches" select="
      not($item_type_codes) or (
        $item_type != '' and
        contains($item_type_codes, $item_type)
      )
    "/>

    <xsl:variable name="item_form_matches" select="
      (
        not($item_form_codes) or
        contains($item_form_codes, $item_form)
      ) and (
        not($item_form_not_codes) or
        not(contains($item_form_not_codes, $item_form))
      )
    "/>

    <xsl:variable name="bib_level_matches" select="
      not($bib_level_codes) or (
        $bib_level != '' and
        contains($bib_level_codes, $bib_level)
      )
    "/>

    <xsl:variable name="vr_format_matches" select="
      not($vr_format_codes) or (
        $vr_format != '' and
        contains($vr_format_codes, $vr_format)
      )
    "/>

    <xsl:variable name="sr_format_matches" select="
      not($sr_format_codes) or (
        $sr_format != '' and
        contains($sr_format_codes, $sr_format)
      )
    "/>

    <xsl:if test="
        $item_type_matches and
        $item_form_matches and
        $bib_level_matches and
        $sr_format_matches and
        $vr_format_matches">
      <xsl:call-template name="add_filter_entry">
        <xsl:with-param name="name" select="$name" />
        <xsl:with-param name="value" select="$value" />
      </xsl:call-template>
    </xsl:if>
  </xsl:template>

  <xsl:template name="leader_value">
    <xsl:param name="offset" /> <!-- zero-based -->
    <xsl:param name="length" />
    <xsl:for-each select="marc:leader">
      <xsl:value-of select="substring(text(), $offset + 1, $length)"/>
    </xsl:for-each>
  </xsl:template>

  <xsl:template name="controlfield_value">
    <xsl:param name="tag" />
    <xsl:param name="offset" /> <!-- zero-based -->
    <xsl:param name="length" />
    <xsl:for-each select="marc:controlfield[@tag=$tag]">
      <xsl:value-of select="substring(text(), $offset + 1, $length)"/>
    </xsl:for-each>
  </xsl:template>

  <!-- Produces a single value for the specific tab/subfields.
       Should only be used in cases where a single value is expected. -->
  <xsl:template name="datafield_value">
    <xsl:param name="tag" />
    <xsl:param name="subfields" />
    <xsl:for-each select="marc:datafield[@tag=$tag]">
      <xsl:call-template name="subfieldSelect">
        <xsl:with-param name="codes">
          <xsl:value-of select="$subfields" />
        </xsl:with-param>
      </xsl:call-template>
      <xsl:text> </xsl:text>
    </xsl:for-each>
  </xsl:template>

  <xsl:template name="subfieldSelect">
    <xsl:param name="codes">abcdefghijklmnopqrstuvwxyz</xsl:param>
    <xsl:param name="delimiter">
      <xsl:text> </xsl:text>
    </xsl:param>
    <xsl:variable name="str">
      <xsl:for-each select="marc:subfield">
        <xsl:if test="contains($codes, @code)">
          <xsl:value-of select="text()"/>
          <xsl:value-of select="$delimiter"/>
        </xsl:if>
      </xsl:for-each>
    </xsl:variable>
    <xsl:value-of select="substring($str,1,string-length($str)-string-length($delimiter))"/>
  </xsl:template>

  <xsl:template name="add_search_entry">
    <xsl:param name="tag" />
    <xsl:param name="field_class" />
    <xsl:param name="index_name" />
    <xsl:param name="index_subfields" />
    <xsl:param name="weight" />
    <xsl:for-each select="marc:datafield[@tag=$tag] |
      marc:datafield[@tag='880']/marc:subfield[@code='6'][starts-with(., $tag)]/..">
      <xsl:text>search </xsl:text>
      <xsl:value-of select="$field_class" /><xsl:text> </xsl:text>
      <xsl:value-of select="$index_name" /><xsl:text> </xsl:text>
      <xsl:call-template name="subfieldSelect">
        <xsl:with-param name="codes">
          <xsl:value-of select="$index_subfields" />
        </xsl:with-param>
      </xsl:call-template>
      <xsl:text>&#xa;</xsl:text><!-- newline -->
    </xsl:for-each>
  </xsl:template>

  <xsl:template name="add_heading_entry">
    <xsl:param name="tag" />
    <xsl:param name="field_class" />
    <xsl:param name="index_subfields" />
    <xsl:param name="weight" />
    <xsl:for-each select="marc:datafield[@tag=$tag] |
      marc:datafield[@tag='880']/marc:subfield[@code='6'][starts-with(., $tag)]/..">
      <xsl:text>heading </xsl:text>
      <xsl:value-of select="$field_class" />

      <xsl:variable name="auth_link">
        <xsl:call-template name="subfieldSelect">
          <xsl:with-param name="codes">0</xsl:with-param>
        </xsl:call-template>
      </xsl:variable>

      <xsl:text> </xsl:text>

      <!-- be sure there are no spaces in the auth link value. -->
      <xsl:variable name="auth_link_trimmed">
        <xsl:value-of select="translate($auth_link, ' ', '')"/>
      </xsl:variable>

      <!-- TODO scrub (CONS) here ? -->

      <xsl:choose>
        <xsl:when test="$auth_link_trimmed != ''">
          <xsl:value-of select="$auth_link" />
        </xsl:when>
        <xsl:otherwise>
          <xsl:text>_</xsl:text>
        </xsl:otherwise>
      </xsl:choose>

      <xsl:text> </xsl:text>

      <xsl:call-template name="subfieldSelect">
        <xsl:with-param name="codes">
          <xsl:value-of select="$index_subfields" />
        </xsl:with-param>
        <xsl:with-param name="delimiter"> -- </xsl:with-param>
      </xsl:call-template>
      <xsl:text>&#xa;</xsl:text><!-- newline -->
    </xsl:for-each>
  </xsl:template>

  <xsl:template name="add_facet_entry">
    <xsl:param name="tag" />
    <xsl:param name="field_class" />
    <xsl:param name="index_name" />
    <xsl:param name="facet_subfields" />
    <xsl:for-each select="marc:datafield[@tag=$tag] |
      marc:datafield[@tag='880']/marc:subfield[@code='6'][starts-with(., $tag)]/..">
      <xsl:text>facet </xsl:text>
      <xsl:value-of select="$field_class"/><xsl:text> </xsl:text>
      <xsl:value-of select="$index_name"/><xsl:text> </xsl:text>
      <xsl:call-template name="subfieldSelect">
        <xsl:with-param name="codes">
          <xsl:value-of select="$facet_subfields" />
        </xsl:with-param>
      </xsl:call-template>
      <xsl:text>&#xa;</xsl:text><!-- newline -->
    </xsl:for-each>
  </xsl:template>

  <!-- Dumps practically the entire document into a single
       keyword|keyword index.
  -->
  <xsl:template name="keyword_full_entry">
    <xsl:text>search keyword keyword </xsl:text>
    <xsl:for-each select="marc:datafield">
      <xsl:call-template name="subfieldSelect" />
      <xsl:text> </xsl:text>
    </xsl:for-each>
    <xsl:text>&#xa;</xsl:text><!-- newline -->
  </xsl:template>

  <!-- print: marc $tag $subfield $value -->
  <xsl:template name="compile_marc">
    <xsl:for-each select="marc:leader">
      <xsl:text>marc LDR _ </xsl:text>
      <xsl:value-of select="text()"/>
    </xsl:for-each>
    <xsl:for-each select="marc:controlfield">
      <xsl:text>marc </xsl:text>
      <xsl:value-of select="@tag" />
      <xsl:text> _ </xsl:text>
      <xsl:value-of select="text()"/>
      <xsl:text>&#xa;</xsl:text><!-- newline -->
    </xsl:for-each>
    <xsl:for-each select="marc:datafield">
      <xsl:variable name="tag" select="@tag" />
      <xsl:for-each select="marc:subfield">
        <xsl:text>marc </xsl:text>
        <xsl:value-of select="$tag" />
        <xsl:text> </xsl:text>
        <xsl:value-of select="@code" />
        <xsl:text> </xsl:text>
        <xsl:value-of select="text()"/>
        <xsl:text>&#xa;</xsl:text><!-- newline -->
      </xsl:for-each>
    </xsl:for-each>
  </xsl:template>


</xsl:stylesheet>


