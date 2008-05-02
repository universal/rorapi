class Rorapi < Autumn::Leaf

#  before_filter :authenticate, :only => [ :reload, :quit ]
 
  ROR_METHODS = Marshal.load(File.read('leaves/api_docs/rails.dump'))
  

  def git_command(stem,sender,reply_to,msg)
    reply_to = msg if msg 
    response = "http://github.com/broughcut/rorapi"
    message(response,reply_to)
  end

  def usage_command(stem,sender,reply_to,msg)
    reply_to = msg if msg 
    response = "'?to_json' '?json:fuzzy' '?to_json:all' '?to_json:se' '?to_json:var' '?method:baz:ba' '?method:args nick' '/rorapi ?method:args'"
    message(response,reply_to)
  end


  def q_command(stem,sender,reply_to,msg,detail=false)
    query = msg.split(' ')
    response = search(query.first,detail)
    if query.size > 1 
      reply_to = query.last.gsub(/#/){}
    end
    message(response,reply_to)
  end

  alias Q_command q_command


  private

  def search(msg,detail)
    query = [*msg.dup.to_s.downcase.split(':')]
    title = query.first
    if query.last == 'fuzzy'
      candidates = ROR_METHODS.select {|it| it[:method].include?(title)}
    else
      candidates = ROR_METHODS.select {|it| it[:method] == title}
    end
    filter(query,candidates,detail) if candidates.any?
  end

  def filter(query,candidates,detail)
    candidates.each do |it|
      #pre-truncated version wants to go in the dump but let's retain flexabiliy over format for now.
      path = it[:path].dup
      it[:truncated_path] = (detail ? path.join('::') : (path[0..-2].map {|p| p.gsub(/[A-Z]/){|z| "|#{z}"}.split('|').map {|i| i[0..2]}.join()}.join(':') << ":#{path.last}").gsub(/^:/){})
      path.map! {|p| p.downcase}
      it[:score] = 0
      query[1..-1].each do |arg|
        it[:score] += 1 if path.include?(arg)
        path.each {|m| it[:score] += 0.5 if m =~ /#{arg}/}
      end
    end
    if query.last == 'all' || query.last == 'fuzzy'
      results = []
      candidates.each {|it|
	results << "#{it[:method]} #{it[:truncated_path]}"
      }
      results.size < 10 ? (showing = results.size) : (showing = 10)
      result = results[0..9].join('; ') 
      result << " (#{showing} of #{results.size})" if results.any?
    else
      result = candidates.sort_by {|it| it[:score]}.last
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
        response = []
        response << result[:method] << "(#{kind})" << doc << result[:tinyuri]
        result = response.compact.join(' ')
      end
    end
    result
  end


  def authenticate_filter(stem, channel, sender, command, msg, opts)
    not ([ :operator, :admin, :founder, :channel_owner ] & [ stem.privilege(channel, sender) ].flatten).empty?
  end
end
