require 'rubygems'
require 'mechanize'

class Scraper
  LabelSchedule = "rpSchedule_ctl01_"
  Labels = {
    num:"lblCNum", 
    name:"lblTitle", 
    instructors:"lblInstructors", 
    desc:"lblDesc",
    days:LabelSchedule+"lblDay", 
    start_time:LabelSchedule+"lblStartTime", 
    end_time:LabelSchedule+"lblEndTime",
    building:LabelSchedule+"lblBuilding", 
    room:LabelSchedule+"lblRoom",
    enroll:"lblTotEnroll",
    cap:"lblTotalCap"}

  ASE = "1"

  attr_accessor :course_class, :dept_class, :school, :term, :num

  def get_dept(dept)
      @form.field_with(:name => "ddlTerm").option_with(:text => @term).click
      @form.field_with(:name => "ddlDept").option_with(:value => dept.short).click
      @form.field_with(:name => "ddlTypes").option_with(:value => "0").click #main course
      @form.field_with(:name => "ddlStatus").option_with(:value => "OP").click #open courses

      @form.field_with(:name => "ddlCreditFrom").option_with(:value => " 00.1").click
      @form.field_with(:name => "ddlCreditTo").option_with(:value => " 16.0").click

      results = @form.click_button
      num = 1
      results.search("//table[@cellpadding='3']").each do |e|
        c = @course_class.new
        c.department = dept
        Labels.each do |sym, label|
          xpath = "//span[@id='rpResults_ctl#{sprintf '%02d', num}_#{label}']"
          val = e.search(xpath).first
          if sym == :num && val
            c.num = val.text.split.last.to_i
          else
            if (sym == :enroll || sym == :cap)
              val = (val ? val.text.to_i : 0)
            elsif val
              val = val.text
            end
            c.send((sym.to_s + "=").to_sym, val)
          end
        end
        if c.num != 0 && c.num
          c.save
        end
        num += 2
      end
  end

  def run
    depts = []

    a = Mechanize.new
    a.get('https://cdcs.ur.rochester.edu/') do |page|
      form = page.form("form1")
        form.field_with(:name => "ddlSchool").option_with(:value => @school).click
        results = form.click_button
      @form = results.form("form1")

      @form.field_with(:name => "ddlDept").options.each do |dept|
        next if depts.size >= @num
        d = @dept_class.where({short:dept.value}).first
        if !d
          d = @dept_class.new
          d.name = dept.text.split(" - ", 2).last
          d.short = dept.value
          d.save
        end
        depts << d if d.name && d.short
      end

      depts.each do |dept|
        get_dept(dept)
      end
    end

    depts
  end

  def self.scrape
    s = Scraper.new
    yield s
    s.run
  end
end

task :scrape => :environment do
  Scraper.scrape do |s|
    s.term = "Spring 2014"
    s.course_class = Course
    s.dept_class = Department
    s.school = Scraper::ASE
    s.num = 1
  end
end