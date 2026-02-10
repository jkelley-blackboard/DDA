// Developed with jQuery's ajax, autocomplete, and jqueryui to faciliate searching within Bb Learn Documentation Pages

$(function()
{
  // Setup the array that parses xml content
  var myArr = [];

  // Parse xml to the array
  function parseXml(xml)
  {
    $(xml).find("link").each(function()
    {
      var thisItem = {};
      thisItem.label = $(this).attr("label");
      thisItem.url = $("input#topLevel").val() + "/" + $(this).attr("url");
      myArr.push(thisItem);
    });
  }

  // Call this function when user selects an auto-populated field (via click or enter)
  function autoComp()
  {
    $("input#searchBox").autocomplete(
    {
      position: { my : "right top", at: "right bottom" },
      source: myArr,
      minLength: 1,

      source: function(request, response)
      {
        var results = $.ui.autocomplete.filter(myArr, request.term);
        if ( !results.length )
        {
          $('.spinner').hide();
        }

        response(results);
      },

      select: function(event, ui)
      {
        // Insert selected item label into the field
        $("input#searchBox").val(ui.item.label);
        // Load current items url into the right frame
        top.frames.contentFrame.location.href = ui.item.url;
      },

      // Show spinner while searching
      search: function(event, ui)
      {
        $('.spinner').show();
      },

      // Hide spinner once item found
      open: function(event, ui)
      {
        $('.spinner').hide();
      }
    });
  }

  $.ajax(
  {
    type: "GET",
    url: $("input#topLevel").val() + "/links.xml",
    dataType: "xml",
    // Call parseXml if it doesn't fail accessing xml
    success: parseXml,
    // Once parsed, call autoComp
    complete: autoComp,
    // If it fails to find xml, alert user
    failure: function(data)
    {
      alert("XML file could not be found");
    }
  });

});
