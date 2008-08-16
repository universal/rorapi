#require 'rubygems'
#require 'hpricot'
#require 'yaml'
require 'uri'
require 'net/http'
require 'hpricot'
require 'helpers/search_api'

class Rorapi < Autumn::Leaf

#  before_filter :authenticate, :only => [ :reload, :quit ]

  def git_command(stem,sender,reply_to,msg)
    message(poll_edge,reply_to)
  end


  def wire_command(stem,sender,reply_to,msg)
    unless @polling
      @polling = true
      go_wire
    end
  end

  def google_command(stem,sender,reply_to,msg)
    doc = get("www.google.com","/search?q=#{URI.encode(msg)}")
    link = doc.at(".g").at(:a)
    result = "#{link.inner_text}: #{link[:href]}"
    message(result,reply_to)
  end

  def usage_command(stem,sender,reply_to,msg)
    reply_to = msg if msg 
    response = "usage: http://gotchunk.blogspot.com/2008/05/rorbby-rubyonrails-api-bot.html"
    message(response,reply_to)
  end

  def define_command(stem,sender,reply_to,define,msg)
    faq = YAML::load(File.read("leaves/api_docs/rails_faq.yml"))
    definition = msg.gsub(/\*$|<<|>>|\s{2,}/){}.strip
    definition_set = definition.split(',')
    definition_set.map! {|it| it.strip}
    if msg =~ /^<</
      faq[define] ||= []
      if faq[define].is_a?(Array)
        faq[define] << definition_set
        faq[define].flatten!
        faq[define].uniq!
      end
    elsif faq[define] && msg =~ /^>>/
      faq[define].delete(definition)
    elsif faq[define] && msg =~ /\*$/ || !faq[define]
      faq[define] = definition
    end
    File.open("leaves/api_docs/rails_faq.yml","w+") {|f| f.puts faq.to_yaml}
  end

  def q_command(stem,sender,reply_to,msg,detail=false)
    query = msg.split(' ')
    reply_to = query[1].gsub(/#/){} if query.size > 1 
    detail = true if query.size > 1
    if query.first =~ /^\?/
      key = query.first.gsub(/\W/){}.to_sym
      faq = YAML::load(File.read("leaves/api_docs/rails_faq.yml"))
      item = faq[key] if faq.has_key?(key)
      response = item
      response = item.join(', ') if item.is_a?(Array)
    else
      response = search(query.first,detail)
    end
     message(response,reply_to)
  end

  alias Q_command q_command

  def rails_edge
    file = File.read("leaves/wire/rails/commits.yml")
    commits = YAML::load(file)
    response = Net::HTTP.get("github.com","/feeds/rails/commits/rails/master")
    xml = Hpricot.XML(response.body)
    commit = {}
    commit[:title] = xml.at(:entry).at(:title).inner_text
    commit[:date] = xml.at(:entry).at(:updated).inner_text
    File.open("leaves/wire/rails/commits.yml","w+") {|f| f.puts commit.to_yaml}
    if commits && !commits.eql?(commit)
      msg = "New edge commit: #{commit[:title]}"
      message(msg,"#rorbot")
      message(msg,"#rubyonrails")
    end
  end

  def rails_tix
    old = YAML::load(File.open("leaves/wire/rails/tix_archive.yml")) 
    tix = YAML::load(File.open("leaves/wire/rails/tix.yml"))
    tix ||= []
    old ||= []
    old << tix
    new_tix = poll_lighthouse
    if !tix.eql?(new_tix)
      ticket = new_tix.first
      prev_version = old.flatten.select {|it| it[:uri] == ticket[:uri]}.first
      return if prev_version && prev_version[:state] == ticket[:state]
      case ticket[:state].to_sym
      when :invalid, :resolved, :incomplete, :open
        about = "Ticket #{ticket[:num]} is #{ticket[:state]}"
      when :new
        about = "New ticket (#{ticket[:num]})"
      end
      p msg = "[Lighthouse] #{about}: #{ticket[:title]} #{ticket[:assigned]} #{ticket[:uri]}"
      message(msg,"#rorbot")
      message(msg,"#rubyonrails")
      message(msg,"#rails-contrib")
    end
  end

  def poll_lighthouse
    server = "rails.lighthouseapp.com"
    page = "/projects/8994-ruby-on-rails/tickets"
    doc = get(server,page)
    tickets = []
    #count = doc.at(".pagination").search(:a)[-2].inner_text.to_i
    count = 1
    count.times do |i|
      doc = get(server,"#{page}?page=#{i+1}")
      (doc/"#open-tickets tr").each do |ticket|
        t = {}
        link = ticket.search(:a)[1]
        t[:state] = ticket.at(".tstate").inner_text.split.last
        t[:num] = ticket.at(".tnum").inner_text.to_i
        t[:title] = link.inner_text
        assignee = ticket.search(:td)[3].inner_text.gsub(/\?/){}
        t[:assigned] = nil
        t[:assigned] = "Assigned: #{assignee}" unless assignee.empty?
        t[:uri] = "http://rails.lighthouseapp.com#{link[:href]}"
        t[:uri] = tinyuri(t[:uri]) if count == 1
        tickets << t
      end
    end
    count > 1 ? title = 'tix_archive' : title = 'tix'
    File.open("leaves/wire/rails/#{title}.yml","w+") {|f| f.puts tickets.to_yaml}
    tickets
  end

  #######
  ## moved modifications from libs/leaf.rb to here:
  #######

  # Invoked when the leaf receives a private (whispered) message. +sender+ is
  # a sender hash.
  def did_receive_private_message(stem, sender, msg)
    if msg =~ /^\?{1,2}[aA-zZ]/
      name = 'q'
      meth = "q_command".to_sym
      msg = msg.gsub(/^\?{1}|quit|reload/){}
      origin = sender.merge(:stem => stem)
      reply_to = sender[:nick]
      detail = true
      stem.message response, reply_to
      response = respond meth, stem, sender, reply_to, msg, detail
    else
      origin = sender.merge(:stem => stem)
      reply_to = sender[:nick]
      msg = msg.gsub(/!/){}
      meth = :usage_command
      stem.message response, reply_to
      response = respond meth, stem, sender, reply_to, msg
    end
  end
  
  # renamed from
  # def parse_for_command(stem, sender, arguments) to
  def command_parse(stem, sender, arguments)
    @last_msgs ||= []
    if arguments[:channel] || options[:respond_to_private_messages]
      reply_to = arguments[:channel] ? arguments[:channel] : sender[:nick]
      #begin rorapi customizations. dry up later
      msg_array = arguments[:message].split
      if arguments[:message] =~ /^\?{1,2}/ && arguments[:message].size > 1
        name = 'q'
        meth = "q_command".to_sym
        msg = arguments[:message].gsub(/^\?{1}/){}
        origin = sender.merge(:stem => stem)
        stem.message response, reply_to
        if run_before_filters(name, stem, arguments[:channel], sender, name, msg) then
          response = respond meth, stem, sender, reply_to, msg
          run_after_filters name, stem, arguments[:channel], sender, name, msg if respond_to? meth
          if response && !response.empty?
            #stem.message response, reply_to
          end
        end #end rorapi
      elsif arguments[:message] =~ /^rorbby,/
        txt = arguments[:message].dup
        txt.gsub!(/rorbby,\s/){}.strip
        define = txt.split(' ')
        term = nil
        msg = nil
        if define.first =~ /:/
          term = define.first.gsub(/:/){}.to_sym
          msg = define[1..-1].join(' ')
        else
          term = define.first.gsub(/\W/){}.to_sym
          msg = define.join(' ')
        end
        origin = sender.merge(:stem => stem)
        stem.message response, reply_to
        response = respond :define_command, stem, sender, reply_to, term, msg
      elsif arguments[:message] == "!rails"
        join_channel "#rubyonrails"
      elsif arguments[:message] == "!contrib"
        join_channel "#rails-contrib"
      elsif arguments[:message] == "!ruby"
        join_channel "#ruby"
      elsif arguments[:message] =~ /^google\?/
        msg = arguments[:message].gsub(/^google\?\s/){}
        stem.message response, reply_to
        response = respond :google_command, stem, sender, reply_to, msg
      elsif arguments[:message] =~ /^![aA-zZ]/
        args = arguments[:message].gsub(/!/){}.split(" ")
        name = args.first
        meth = "#{name}_command".to_sym
        msg = args.last if args.size > 1
        origin = sender.merge(:stem => stem)
        if run_before_filters(name, stem, arguments[:channel], sender, name, msg) then
          response = respond meth, stem, sender, reply_to, msg
          run_after_filters name, stem, arguments[:channel], sender, name, msg if respond_to? meth
          if response and not response.empty? then
            #stem.message response, reply_to
          end
        end
      end
      if arguments[:channel] == '#rubyonrails'
        @last_msgs << {:msg => arguments[:message], :nick => sender[:nick]}
        @last_msgs.shift if @last_msgs.size > 10
      end
    end
  end

  #######
  ## end of moved code
  #######

  private
  def go_wire
    while @polling
      rails_tix
      rails_edge
      sleep 300
    end
  end


  def get(server,page) #will class this out to eventmachine client
    response = Net::HTTP.get(server,page)
    Hpricot(response)
  end

  def tinyuri(uri)
    file = File.read("leaves/wire/rails/tinyuris.yml")
    tix = YAML::load(file)
    tix ||= {}
    unless tix[uri]
      doc = get("tinyurl.com","/create.php?url=#{uri}")
      tix[uri] = (doc/:blockquote)[1].at(:b).inner_text
      File.open("leaves/wire/rails/tinyuris.yml","w+") {|f| f.puts tix.to_yaml}
    end
    tix[uri]
  end

  def authenticate_filter(stem, channel, sender, command, msg, opts)
    not ([ :operator, :admin, :founder, :channel_owner ] & [ stem.privilege(channel, sender) ].flatten).empty?
  end
end
