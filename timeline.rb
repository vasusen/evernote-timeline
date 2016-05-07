#
# A simple app to add events to some timeline on Evernote
# The timeline is represented as a note.
# To run (Unix):
#   ruby timeline.rb
#

require 'evernote-thrift'
require 'nokogiri'
require 'optparse'
require 'optparse/time'

## SETUP VARS ##

# Change MODE to :production for production
MODE = :sandbox

# Real applications authenticate with Evernote using OAuth, but for the
# purpose of exploring the API, you can get a developer token that allows
# you to access your own Evernote account. To get a developer token, visit
# https://sandbox.evernote.com/api/DeveloperToken.action and
# https://www.evernote.com/api/DeveloperToken.action

sandbox_developer_token = ENV['EVERNOTE_SANDBOX_DEVELOPER_TOKEN']
production_developer_token = ENV['EVERNOTE_PRODUCTION_DEVELOPER_TOKEN']

if MODE == :production
	auth_token = production_developer_token
else
	auth_token = sandbox_developer_token
end

if MODE == :production
	evernote_host = "www.evernote.com"
else
	evernote_host = "sandbox.evernote.com"
end
user_store_url = "https://#{evernote_host}/edam/user"


## COMMAND LINE OPTIONS ##

# command line options
# --name -n,-t name of timeline
# --date -d date of event
# --message -m,-e message for that event
options = {}

opt_parser = OptionParser.new do |opt|  
  opt.banner = "Usage: opt_parser [OPTIONS]"
  opt.separator  ""
  opt.separator  ""
  opt.separator  "Options"

  opt.on("-n","--name NAME","which timeline do you want to post to, switches to 'default' if not provided.") do |name|
    options[:name] = name
  end

  opt.on("-t","--timeline TIMELINE","which timeline do you want to post to, switches to 'default' if not provided.") do |name|
    options[:name] = name
  end

  opt.on("-m","--message MESSAGE","what event do you want to post to timeline") do |message|
    options[:message] = message
  end

  opt.on("-e","--event EVENT","what event do you want to post to timeline") do |message|
    options[:message] = message
  end

  opt.on("-d","--date DATE", Time, "date of event in format yyyy-mm-dd, defaults to today") do |time|
    options[:time] = time
  end

  opt.on("-h","--help","help") do
    puts opt_parser
    exit
  end
end

opt_parser.parse!  
timeline_name = options[:name] || 'default'
message = options[:message]

if options[:time] 
	note_time = "#{options[:time].strftime('%Y-%m-%d')}"
else
	note_time = "#{Time.now.strftime('%Y-%m-%d')}"
end

if message.empty?
	puts "message is required"
	puts opt_parser
	exit
end

user_store_transport = Thrift::HTTPClientTransport.new(user_store_url)
user_store_protocol = Thrift::BinaryProtocol.new(user_store_transport)
user_store = Evernote::EDAM::UserStore::UserStore::Client.new(user_store_protocol)

# Exit if Evernote version not okay
version_ok = user_store.checkVersion("Evernote EDAMTest (Ruby)",
				   Evernote::EDAM::UserStore::EDAM_VERSION_MAJOR,
				   Evernote::EDAM::UserStore::EDAM_VERSION_MINOR)
exit unless version_ok


# Get the URL used to interact with the contents of the user's account
# When your application authenticates using OAuth, the NoteStore URL will
# be returned along with the auth token in the final OAuth request.
# In that case, you don't need to make this call.
note_store_url = user_store.getNoteStoreUrl(auth_token)
note_store_transport = Thrift::HTTPClientTransport.new(note_store_url)
note_store_protocol = Thrift::BinaryProtocol.new(note_store_transport)
note_store = Evernote::EDAM::NoteStore::NoteStore::Client.new(note_store_protocol)


# Loop thru all notebooks to find guid of notebook called "Timelines"
notebooks = note_store.listNotebooks(auth_token)
timelines_notebook = nil
notebooks.each do |notebook|
  # store the timelines notebook in var if it exists
  if notebook.name == "Timelines"
    timelines_notebook = notebook
  end
end

# If notebook for "Timelines" does not exist, create it.
if timelines_notebook == nil
  notebook = Evernote::EDAM::Type::Notebook.new
  notebook.name = "Timelines"

  begin
  	timelines_notebook = note_store.createNotebook(auth_token, notebook)
  rescue Evernote::EDAM::Error::EDAMUserException => edue
    ## Something was wrong with the note data
    ## See EDAMErrorCode enumeration for error code explanation
    ## http://dev.evernote.com/documentation/reference/Errors.html#Enum_EDAMErrorCode
    puts "EDAMUserException: #{edue.errorCode}"
  end
end

## Find Note with timeline_name ##
note_filter = Evernote::EDAM::NoteStore::NoteFilter.new
note_filter.words = timeline_name

note_filter_result_set = Evernote::EDAM::NoteStore::NotesMetadataResultSpec.new
note_filter_result_set.includeTitle = true

timeline_note = nil
begin
  notes = note_store.findNotesMetadata(auth_token,
      ::Evernote::EDAM::NoteStore::NoteFilter.new, 0, 100,
      note_filter_result_set).notes
  notes.each do |note|
    # compare name of note ignoring case
    if 0 == timeline_name.casecmp(note.title)
      timeline_note = note_store.getNote(auth_token, note.guid, true, false, false, false)
    end
end
rescue Evernote::EDAM::Error::EDAMUserException => edue
  puts "EDAMUserException: #{edue.errorCode}"
end

## if Timeline does not exist, create it
if timeline_note == nil
  note = Evernote::EDAM::Type::Note.new
  note.title = timeline_name.capitalize
  note.notebookGuid = timelines_notebook.guid
  note.content = <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd">
<en-note>
  <p><strong>#{note_time}</strong> #{message}</p>
</en-note>
EOF

  begin
    created_note = note_store.createNote(auth_token, note)
  rescue Evernote::EDAM::Error::EDAMUserException => edue
    puts "EDAMUserException: #{edue.errorCode}"
  end
  puts "Successfully created a new note with GUID: #{created_note.guid}"

## Timeline note exists, read it.
else
  # Read note
  note = note_store.getNote(auth_token, timeline_note.guid, true, false, false, false)
  note_content = note.content

  # update note
  xml_doc = Nokogiri::XML(note_content)
  first_elem = xml_doc.css('en-note').children.first
  if first_elem
  	first_elem.add_previous_sibling "<p><strong>#{note_time}</strong> #{message}</p>"
  else
  	xml_doc.css('en-note').first.add_child "<p><strong>#{note_time}</strong> #{message}</p>"
  end
  #first_elem = xml_doc.css('p').first
  #first_elem.add_previous_sibling "<p><strong>#{note_time}</strong> #{message}</p>"

  note.content = xml_doc.to_s
  note_store.updateNote(auth_token, note)
end

puts "Message posted. Have a good day."


