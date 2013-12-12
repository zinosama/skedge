class MainController < ApplicationController
	def do_search(type_search, status_search, name_search, dept_search, num_search, instructor_search, term_search)
		Course.joins{department}.where do
			[
				num =~ "#{num_search}%",
				term_search.presence && term == term_search,
				name_search.presence && name =~ "%#{name_search}%",
				dept_search.presence && department.short =~ "#{dept_search.upcase}%",
				type_search.presence && course_type == type_search,
				status_search.presence && status == status_search,
				status != Course::Status::Cancelled,
				instructor_search.presence && instructors =~ "%#{instructor_search}%"
			].compact.reduce(:&)
		end.to_a
	end

	def search_for_courses(query)
		if match = (query.match /rand\((\d*)\)/)
			num = [match[1].to_i, 1].max
			offset = rand(Course.count)
			return Course.limit(num).where {course_type == Course::Type::Course}.order("RANDOM()").to_a
		end

		type_search = Course::Type::Course
		status_search = nil
		name_search = nil
		dept_search = nil
		num_search = nil
		instructor_search = nil
		term_search = nil

		instructor_regex = /instructor:\s*([A-Za-z'-_]*)/i
		if (match = query.match instructor_regex)
			instructor_search = match[1]
			query = query.gsub(instructor_regex,"") #remove from the query
		end

		term_regex = /term:\s*([A-Za-z'-_]*)/i
		if (match = query.match term_regex)
			term_search = match[1]
			term_search = Course::Term::Terms[term_search.titleize]
			query = query.gsub(term_regex,"") #remove from the query
		end

		match = query.match /^([A-Za-z]*)\s*(\d+[A-Za-z]*|)\s*$/
		if match && (match[1].size <= 3 || !match[2].empty?) #either the dept length is <= 3 OR we have some numbers
			dept_search = match[1] if !match[1].empty?
			num_search = match[2] if !match[2].empty?
		else
			name_search = query
		end

		do_search(type_search, status_search, name_search, dept_search, num_search, instructor_search, term_search)
	end

	def filter(courses)
		#TODO optimize!
		courses.delete_if do |c|
			sister = c.sister_course
			sister && courses.include?(sister) && (c.year < sister.year || (c.year == sister.year && c.term > sister.term))
		end
		courses.each do |c|
			courses.delete_if do |c2|
				c2 != c &&
				c2.num == c.num &&
				c2.department_id == c.department_id &&
				c2.term == c.term &&
				c2.year == c.year
			end
		end
	end

	def index
		@query = params[:query].try(:strip)
		@query = nil if @query && @query.empty?
		if @query
			@courses = filter(search_for_courses(@query))
		else
			@depts = Department.all
		end
	end
end
