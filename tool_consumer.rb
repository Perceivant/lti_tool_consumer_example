require 'sinatra'
require 'ims/lti'
require 'digest/md5'
# must include the oauth proxy object
require 'oauth/request_proxy/rack_request'
require 'pp'

enable :sessions

get '/' do
  redirect to('/tool_config')
end

post '/set_name' do
  session['username'] = params['username'] || 'Bob'
  redirect to('/tool_config')
end

get '/tool_config' do
  @message = params['message']
  erb :tool_config
end

post '/tool_launch' do
  if %w{tool_name launch_url consumer_key consumer_secret}.any?{|k|params[k].nil? || params[k] == ''}
    redirect to('/tool_config?message=Please%20set%20all%20values')
    return
  end

  tc = IMS::LTI::ToolConfig.new(:title => params['tool_name'], :launch_url => params['launch_url'])
  tc.set_custom_param('message_from_sinatra', 'hey from the sinatra example consumer')
  @consumer = IMS::LTI::ToolConsumer.new(params['consumer_key'], params['consumer_secret'])
  @consumer.set_config(tc)

  host = request.scheme + "://" + request.host_with_port

  # Set some launch data from: http://www.imsglobal.org/LTI/v1p1pd/ltiIMGv1p1pd.html#_Toc309649684
  # Only this first one is required, the rest are recommended
  @consumer.resource_link_id = "thisisuniquetome"
  @consumer.launch_presentation_return_url = host + '/tool_return'
  @consumer.lis_person_name_given = params['username']
  @consumer.user_id = Digest::MD5.hexdigest(params['username'])
  @consumer.roles = "Instructor"
  @consumer.context_id = "bestcourseever"
  @consumer.context_title = "Example Sinatra Tool Consumer"
  @consumer.tool_consumer_instance_name = "Frankie"
  @consumer.tool_consumer_instance_guid = params['tool_consumer_instance_guid'] || "wut.testing.com"
  @consumer.tool_consumer_info_product_family_code = params['tool_consumer_info_product_family_code'] || 'testthingy'
  @consumer.set_custom_param('lis_person_contact_email_primary', 'oi@wut.testing.com')
  @consumer.lti_message_type = params['lti_message_type']

  if @consumer.lti_message_type == 'ContentItemSelectionResponse'
    @consumer.set_non_spec_param('content_items', "{\"@context\":\"http://purl.imsglobal.org/ctx/lti/v1/ContentItemPlacement\", \"@graph\":[{\"@ty
pe\":\"ContentItemPlacement\", \"placementOf\":{\"@id\":\"https://example.com/remote_file.imscc\", \"@type\":\"FileItem\", \"
mediaType\":\"application/zip\", \"title\":\"Cool Course\"}}]}")
  end

  if @consumer.lti_message_type == 'ContentItemSelectionRequest'
    @consumer.set_non_spec_param('accept_media_types', 'application/zip')
    @consumer.set_non_spec_param('accept_presentation_document_targets', '')
    @consumer.set_non_spec_param('content_item_return_url', @consumer.launch_presentation_return_url)
    @consumer.set_non_spec_param('accept_copy_advice', 'true')
  end

  if params['assignment']
    @consumer.lis_outcome_service_url = host + '/grade_passback'
    @consumer.lis_result_sourcedid = "oi"
  end

  @autolaunch = !!params['autolaunch']

  erb :tool_launch
end

get '/tool_return' do
  @error_message = params['lti_errormsg']
  @message = params['lti_msg']
  puts "Warning: #{params['lti_errorlog']}" if params['lti_errorlog']
  puts "Info: #{params['lti_log']}" if params['lti_log']

  erb :tool_return
end

post '/grade_passback' do
  # Need to find the consumer key/secret to verify the post request
  # If your return url has an identifier for a specific tool you can use that
  # Or you can grab the consumer_key out of the HTTP_AUTHORIZATION and look up the secret
  # Or you can parse the XML that was sent and get the lis_result_sourcedid which
  # was set at launch time and look up the tool using that somehow.

  req = IMS::LTI::OutcomeRequest.from_post_request(request)
  sourcedid = req.lis_result_sourcedid

  # todo - create some simple key management system
  consumer = IMS::LTI::ToolConsumer.new('test', 'secret')

  if consumer.valid_request?(request)
    if consumer.request_oauth_timestamp.to_i - Time.now.utc.to_i > 60*60
      throw_oauth_error
    end
    # this isn't actually checking anything like it should, just want people
    # implementing real tools to be aware they need to check the nonce
    if was_nonce_used_in_last_x_minutes?(consumer.request_oauth_nonce, 60)
      throw_oauth_error
    end

    res = IMS::LTI::OutcomeResponse.new
    res.message_ref_identifier = req.message_identifier
    res.operation = req.operation
    res.code_major = 'success'
    res.severity = 'status'

    if req.replace_request?
      res.description = "Your old score of 0 has been replaced with #{req.score}"
    elsif req.read_request?
      res.description = "You score is 50"
      res.score = 50
    elsif req.delete_request?
      res.description = "You score has been cleared"
    else
      res.code_major = 'unsupported'
      res.severity = 'status'
      res.description = "#{req.operation} is not supported"
    end

    headers 'Content-Type' => 'text/xml'
    res.generate_response_xml
  else
    throw_oauth_error
  end
end

def throw_oauth_error
  response['WWW-Authenticate'] = "OAuth realm=\"http://#{request.env['HTTP_HOST']}\""
  throw(:halt, [401, "Not authorized\n"])
end

def was_nonce_used_in_last_x_minutes?(nonce, minutes=60)
  # some kind of caching solution or something to keep a short-term memory of used nonces
  false
end
