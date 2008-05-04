require 'net/http'
require 'hpricot'
require 'leaves/search_api'
class Rorapi < Autumn::Leaf

#  before_filter :authenticate, :only => [ :reload, :quit ]

  def git_command(stem,sender,reply_to,msg)
    message(poll_edge,reply_to)
  end


  def wire_command(stem,sender,reply_to,msg)
    return unless sender[:nick] == 'brough'
    300.times do #hmm :/
      rails_tix
      rails_edge
      sleep 300
    end
  end

  def usage_command(stem,sender,reply_to,msg)
    reply_to = msg if msg 
    response = "'?to_json' '?json:fuzzy' '?to_json:all' '?to_json:se' '?to_json:var' '?method:baz:ba' '?method:args nick' '/rorapi ?method:args'"
    message(response,reply_to)
  end

  def define_command(stem,sender,reply_to,define,msg)
    faq = YAML::load(File.read('leaves/api_docs/rails_faq.yml'))
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
      faq = YAML::load(File.read('leaves/api_docs/rails_faq.yml'))
      item = faq.select {|it| it == query.first.gsub(/\W/){}.to_sym}.values.first
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
      msg = "New edge commit: #{commit[:title]} #{Date.parse(commit[:date]).strftime("%I%p %e/%m")}"
      message(msg,"#rubyonrails")
    end
  end

  def rails_tix
    file = File.read("leaves/wire/rails/tix.yml")
    tix = YAML::load(file)
    new_tix = poll_lighthouse
    if !tix.eql?(new_tix)
      ticket = new_tix.first
      if ticket[:state] != "new"
        prev_version = tix.select {|it| it[:uri] == ticket[:uri]}.first
        return if prev_version[:state] == ticket[:state]
      end
      case ticket[:state].to_sym
      when :invalid, :resolved
        about = "Ticket #{ticket[:num]} is #{ticket[:state]}"
      when :new
        about = "New ticket (#{ticket[:num]})"
      end
      msg = "Lighthouse: #{about}: #{ticket[:title]} #{ticket[:assigned]} #{ticket[:uri]}"
      message(msg,"#rubyonrails")
    end
  end

  def poll_lighthouse
    server = "rails.lighthouseapp.com"
    page = "/projects/8994-ruby-on-rails/tickets"
    doc = get(server,page)
    tickets = []
    doc = get(server,"#{page}")#?page=#{i+1}")
    if doc
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
        t[:uri] = tinyuri(t[:uri])
        tickets << t
      end
    end
    File.open("leaves/wire/rails/tix.yml","w+") {|f| f.puts tickets.to_yaml}
    tickets
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
