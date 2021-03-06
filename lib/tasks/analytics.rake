require 'json'

def data(query)
  data = []
  ActiveRecord::Base.connection.execute(query).each do |result| 
    current = Date.parse(result['day'])
    if data.any?
      last = data.last[:time]
      diff = current - last
      if diff > 1
        (diff - 1).to_i.times do |i|
          data << {time: last+(i+1), count: 0 }
        end
      end
    end
    data << { time: current, count: result['count'].to_i }
  end
  data
end

def print(outer, inner, file, collection)
  analytics_root = File.join(Rails.root, "analytics")
  Dir.mkdir(analytics_root) unless File.directory?(analytics_root)

  dir = File.join(analytics_root, outer)
  Dir.mkdir(dir) unless File.directory?(dir)

  dir = File.join(dir, inner)
  Dir.mkdir(dir) unless File.directory?(dir)

  file = File.join(dir, file) + ".txt"
  
  File.open(file, 'w') do |file|
    collection.each_with_index do |a, b|
      row = block_given? ? (yield a, b) : a
      file.puts(row.join("\t"))
    end
  end
end

def print_basic(folder, file, name, property=nil, value=nil)
  value = [value] if not value.is_a? Array
  or_clauses = value.map do |val|
    "properties->'#{property}' = '#{val.inspect}'"
  end.join(" OR ")
  and_clause = property ? "AND (#{or_clauses})" : nil
  sql = <<-SQL
  SELECT date_trunc('day', time) AS "day", count(*)
  FROM ahoy_events
  WHERE name = '#{name}' #{and_clause}
  GROUP BY 1
  ORDER BY 1;
  SQL

  print("basic", folder, file, data(sql)) do |row|
    [row[:time], row[:count]]
  end
end

def count_search_types_in_query(types=Hash.new(0), query)
  q = Course.text_to_query(query)

  types[:description] += 1   if q.attrs[:description]
  types[:credits] += 1       if q.attrs[:credits] != { :> => "0" }
  types[:department_id] += 1 if q.attrs[:department_id]
  types[:crosslisted] += 1   if q.attrs[:crosslisted]
  types[:crn] += 1           if q.attrs[:sections].try(:[], :crn)
  types[:year] += 1          if q.attrs[:year]
  types[:number] += 1        if q.attrs[:number]
  types[:instructor] += 1    if q.attrs[:sections].try(:[], :instructors)
  types[:term] += 1          if q.attrs[:term]
  types[:random] += 1        if q.orders == ["RANDOM()"]
  types[:w] += 1             if q.attrs[:number].try(:end_with?, "W%")
  types[:title] += 1         if q.attrs[:title]

  types
end

namespace :analytics do
  task :social => [:environment] do
    print_basic("social", "integrations-old", "$old-user-fb")
    print_basic("social", "integrations-new", "$new-user", "fb", true)
  end

  task :basic => [:environment] do
    print_basic(".", "old_search", "Search") # old search
    print_basic(".", "submit", "$submit") # search

    print_basic("scheduling", "add", "$click", "add", true)
    print_basic("scheduling", "remove", "$click", "add", false)
    print_basic("scheduling", "readd", "$click", "readd", true)

    print_basic("searchbyclick", "instructor", "$click", "name", "instructor")
    print_basic("searchbyclick", "block", "$click", "name", "block")
    print_basic("searchbyclick", "prerequisites", "$click", "name", "prerequisites")
    print_basic("searchbyclick", "crosslisted", "$click", "name", "crosslisted")

    print_basic("export", "gcal", "$click", "name", "export-ics")
    print_basic("export", "ics", "$click", "name", "export-gcal")
    print_basic("export", "image", "$click", "name", ["export-image", "export-image-jpg", "export-image-png"])

    print_basic(".", "subcourses", "$click", "hide", false)
  end

  def clicks_to_add(types_of_search: false, 
                    include_bookmarks: false,
                    search_condition: nil,
                    subsection_ratio_for_n_navs: nil)

    clicks2add = {}
    nav_names = ["crosslist", "instructor", "prereqs"]
    num_types_of_search_dt = {}

    n_nav_subsections = 0
    n_nav_mainsections = 0

    User.all.each do |u|
      query = <<-SQL
        select * from ahoy_events
        where user_id = '#{u.id}' and (name = '$submit' or name = '$click' or name = '$bookmark')
        order by time asc;
      SQL

      results = ActiveRecord::Base.connection.execute(query)

      first_add = results.to_a[0]
      if first_add
        # first event will always be an add, since there's no user ID before that.
        # prepend the events that occurred before the initial add
        first_event_query = <<-SQL
          select * from ahoy_events
          where visit_id = '#{first_add['visit_id']}' 
          and (name = '$submit' or name = '$click')
          and time < '#{first_add['time']}'
          order by time asc;
        SQL

        first_events = ActiveRecord::Base.connection.execute(first_event_query)
        results = first_events.to_a + results.to_a
      end

      navs = 0
      current_visit = nil
      failed_search_condition = false

      results.each do |result|
        # compute diversity of search type over time per user
        properties = JSON.parse(result["properties"])

        if types_of_search
          if result["name"] == "$submit"
            types = count_search_types_in_query(properties["q"])
            types.delete :department_id
            types.delete :number
            num_types_of_search_dt[u.id] ||= []
            num_types_of_search_dt[u.id] << types.length
          end
        else
          if current_visit && result["visit_id"] != current_visit
            navs = 0
          end
          current_visit = result["visit_id"]

          # compute number of navigations between adds
          if result["name"] == "$click" && nav_names.include?(properties["name"])
            navs += 1
          end

          if result["name"] == "$click" && properties["name"] == "block"
            navs = 0
            block = true
          else
            block = false
          end

          if result["name"] == "$click" && 
             properties["add"] && 
             !failed_search_condition &&
             !block

            clicks2add[u.id] ||= []
            clicks2add[u.id][navs] = clicks2add[u.id][navs].to_i + 1

            if navs == subsection_ratio_for_n_navs
              if section = Section.find_by(crn: properties["crn"])
                if section.section_type != Section::Type::Course
                  n_nav_subsections += 1
                else
                  n_nav_mainsections += 1
                end
              end
            end

            navs = 0
          end

          if result["name"] == "$bookmark" && include_bookmarks
            clicks2add[u.id] ||= []
            clicks2add[u.id][navs] = clicks2add[u.id][navs].to_i + 1
            
            navs = 0
          end

          if result["name"] == "$click" && properties["name"] == "instructor"
            if include_bookmarks
              failed_search_condition = false
            else
              failed_search_condition = true
            end
          end

          if result["name"] == "$submit"
            if !search_condition || search_condition.call(properties["q"])
              navs += 1
              failed_search_condition = false
            else
              # Reset
              failed_search_condition = true
              navs = 0
            end
          end
        end
      end
    end

    if types_of_search
      num_types_of_search_dt
    elsif subsection_ratio_for_n_navs
      {subsections: n_nav_subsections, mainsections: n_nav_mainsections}
    else
      clicks2add
    end
  end

  task :n_nav_subsections => [:environment] do
    direct_condition = -> (query) do
      q = Course.text_to_query(query)
      (q.attrs[:department_id] && q.attrs[:number]) ||
       q.attrs[:title]
    end

    3.times do |n|
      d_nav_subsection_ratio = clicks_to_add(search_condition: direct_condition,
                                             subsection_ratio_for_n_navs: n)

      b_nav_subsection_ratio = clicks_to_add(include_bookmarks: true,
                                             search_condition: -> (q) {
                                               !direct_condition.call(q)
                                              },
                                             subsection_ratio_for_n_navs: n)

      print("per_person", ".", "direct_#{n}_nav_subsection_ratio", d_nav_subsection_ratio)

      print("per_person", ".", "browse_#{n}_nav_subsection_ratio", b_nav_subsection_ratio)
    end
  end

  task :per_person => [:environment] do
    num_types_of_search_dt = clicks_to_add(types_of_search: true)

    clicks2add = clicks_to_add
    clicks2add_or_bkmk = clicks_to_add(include_bookmarks: true)

    direct_condition = -> (query) do
      q = Course.text_to_query(query)
      (q.attrs[:department_id] && q.attrs[:number]) ||
       q.attrs[:title]
    end

    direct_clicks2add = clicks_to_add(search_condition: direct_condition)
    browse_clicks2add_or_bkmk = clicks_to_add(include_bookmarks: true,
                                              search_condition: -> (q) {
                                                !direct_condition.call(q)
                                               })

    print("per_person", ".", "clicks2add", clicks2add) do |x, idx|
      user, values = x
      [user, *values]
    end

    print("per_person", ".", "clicks2add_or_bkmk", clicks2add_or_bkmk) do |x, idx|
      user, values = x
      [user, *values]
    end

    print("per_person", ".", "direct_clicks2add", direct_clicks2add) do |x, idx|
      user, values = x
      [user, *values]
    end

    print("per_person", ".", "browse_clicks2add_or_bkmk", browse_clicks2add_or_bkmk) do |x, idx|
      user, values = x
      [user, *values]
    end

    print("per_person", ".", "search_types", num_types_of_search_dt) do |x, idx|
      user, values_dt = x
      [user, *values_dt]
    end
  end

  task :search => [:environment] do
    query = <<-SQL
      select * from ahoy_events
      where name = '$submit';
    SQL

    empty_queries = []
    empty = 0
    total = 0

    types = Hash.new(0)

    ActiveRecord::Base.connection.execute(query).each do |result|
      properties = JSON.parse(result["properties"])

      begin
        q = Course.sk_query(properties["q"])
        if (q.empty?)
          empty_queries << [properties["q"]]
          empty += 1
        end
        total += 1
      rescue Exception => e
      end

      count_search_types_in_query(types, properties["q"])
    end

    # percentage of searches that come up empty
    print("search", ".", "empty", {empty:empty, nonempty:total - empty})

    print("search", ".", "empty_queries", empty_queries)

    # percentage of search types
    print("search", ".", "types", types)
  end
end

task :analytics => ["analytics:basic",
                    "analytics:per_person",
                    "analytics:search",
                    "analytics:social"]

