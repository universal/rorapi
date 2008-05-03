  
  RAILS_API = Marshal.load(File.read('leaves/api_docs/rails.dump'))

  RUBY_API = Marshal.load(File.read('leaves/api_docs/ruby.dump'))

  def search(msg,detail)
    query = [*msg.dup.to_s.downcase.split(':')]
    title = query.first
    lang = query[1]
    if lang && lang == 'ruby' && query.last == 'fuzzy'
      candidates = RUBY_API.select {|it| it[:method].include?(title)}
    elsif lang == 'ruby'
      candidates = RUBY_API.select {|it| it[:method] == title}
    elsif query.last == 'fuzzy'
      candidates = RAILS_API.select {|it| it[:method].include?(title)}
    else
      candidates = RAILS_API.select {|it| it[:method] == title}
    end
    filter(query,candidates,detail) if candidates.any?
  end

  def filter(query,candidates,detail)
    candidates.each do |it|
      path = it[:path].dup
      it[:truncated_path] = path[0..-2].map {|p| p.gsub(/[A-Z]/){|z| "|#{z}"}.split('|').map {|i| i[0..2]}.join()}.join(':')
      path.map! {|p| p.downcase}
      it[:score] = 0
      query[1..-1].each do |arg|
        it[:score] += 1 if path.include?(arg)
        path.each {|m| it[:score] += 0.5 if m =~ /#{arg}/}
      end
    end
    if query.last == 'all' || query.last == 'fuzzy'
      results = []
      candidates.each {|it| results << "#{it[:method]} #{it[:truncated_path]}"}
      result = results[0..9].join('; ') 
      results.size < 10 ? (showing = results.size) : (showing = 10)
      result << " (#{showing} of #{results.size})" if results.any?
    else
      results = candidates.sort_by {|it| it[:score]}
      at = query.join.gsub(/\D/){}
      at ? result = results[at.to_i] : result = result.first
      if result
        rpath = result[:path].dup
        if rpath.size > 1
          kind = rpath[-2..-1].join('::')
        else
          kind = rpath
        end
        doc = result[:description]
        doc.gsub!(/\s{1,}/,' ').gsub!(/\n/){} if doc
        if doc && !detail
          doc = "#{doc[0..100]}..."
        end
        egs = result[:examples] if result[:examples]
        if egs && !detail
          egs = "#{egs[0..1].join('; ')}..."
        elsif egs
          egs = egs.join('; ')
        end
        response = []
        response << result[:method] << "(#{kind})" << result[:tinyuri] << doc << egs
        result = response.compact.join(' ')
      end
    end
    result
  end
