// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or vendor/assets/javascripts of plugins, if any, can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// compiled file.
//
// Read Sprockets README (https://github.com/sstephenson/sprockets#sprockets-directives) for details
// about supported directives.
//
//= require jquery
//= require jquery_ujs
//= require bootstrap
//= require_tree .

function prof_email(i)
{
	console.log(i);
}

function prof_rmp(i)
{
	var url = "http://www.ratemyprofessors.com/SelectTeacher.jsp?searchName="+i+"&search_submit1=Search&sid=1331";
	window.open(url);
}

function prof_search(i)
{
	$("#search-input").val("instructor:"+i);
	$("#form").submit();
}

function prepareModal()
{
	$("#modal-alert").hide();
	$("#modal-submit").removeAttr("disabled");
	$("#modal-submit").val("Submit").removeClass('btn-success').addClass('btn-primary');
	$("#modal-email").val("");
	$("#modal-contents").val("");
}

function splashtoggle(selector)
{
	if (selector != null && $(selector).css('display') == 'none')
	{
		$('#info').hide();
		$('#departments').hide();
		$('#splash-space').hide();	
		$(selector).show();
	}
	else
	{
		$('#info').hide();
		$('#departments').hide();
		$('#splash-space').show();	
		if (selector != null)
			$(selector).hide();		
	}
}

$(function() 
{
    $('.tooltippy').tooltip();
    $('.dropdown-toggle').dropdown();
	$('.pop').popover({html:true});
    $(".dropdown-menu li a").click(function(){
		var selText = $(this).text();
		var display = selText.split("(")[0].trim();
		if (selText == "Course #" || selText == "Any" || selText == "Either")
		{
			$(this).parents('.filter').removeClass('filter-bold');
		}
		else
		{
			$(this).parents('.filter').addClass('filter-bold');
		}
		$(this).parents('.btn-group').find('.dropdown-toggle').html(display+' <span class="caret"></span>');
		$(this).parents('.btn-group').find('.dropdown-value').val(selText);
		$('#form').submit();
	});

});

$('html').on('click', function (e) {
    $('.pop').each(function () {
    	//the 'is' for buttons that trigger popups
        //the 'has' for icons within a button that triggers a popup
        if (!$(this).is(e.target) && $(this).has(e.target).length === 0 && $('.popover').has(e.target).length === 0) {
            $(this).popover('hide');
        }
    });
});

initialize();

$(document).ready(function() {
	compute_buttons();
});

