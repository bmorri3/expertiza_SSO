class LtiController < ApplicationController
  include AuthHelper # This gives access to AuthController methods

  skip_before_action :verify_authenticity_token, only: [:launch]
  skip_before_action :authorize, only: [:launch]
  after_action :allow_iframe, only: [:launch]

  def launch
    begin
      authenticator = IMS::LTI::Services::MessageAuthenticator.new(
        request.url,
        request.request_parameters,
        ENV['LTI_SHARED_ENCODER']
      )

      #Check if the signature is valid
      if authenticator.valid_signature?
        # Retrieve user information from LTI parameters
        user_email = params['lis_person_contact_email_primary']
        username, domain = separate_email(user_email)

        if valid_domain?(domain)
          authenticate_and_login_user(username)
        else
          redirect_to root_path, alert: 'Invalid domain'
        end
      else
        redirect_to root_path, alert: 'Invalid LTI signature'
      end
    rescue => e
      Rails.logger.error "Error in LTI launch: #{e.message}"
      redirect_to root_path, alert: 'An error occurred during login'
    end
  end

  private

  def allow_iframe
    response.headers.except! 'X-Frame-Options'
  end

  def separate_email(email)
    return [nil, nil] if email.blank?
    parts = email.split('@')
    parts.length == 2 ? parts : [nil, nil]
  end

  def valid_domain?(domain)
    domain == "ncsu.edu"
  end

  def authenticate_and_login_user(username)
    # Gets the user if they exist in Expertiza, else null
    user = User.find_by(name: username)
    if user
      # Log the user in
      session[:user] = user  # Store the entire user object, not just the username
      AuthController.set_current_role(user.role_id, session)
      ExpertizaLogger.info LoggerMessage.new('', user.name, 'Login successful via LTI')

      redirect_to "#{ENV['LTI_BASE_URL']}/student_task/list", notice: 'Logged in successfully via LTI'

    else
      redirect_to root_path, alert: 'User not found in Expertiza. Please register first.'
    end

    rescue => e
      Rails.logger.error "Error in LTI launch.authenticate_and_login: #{e.message}"
      redirect_to root_path, alert: 'An error occurred during login'
  end
end
