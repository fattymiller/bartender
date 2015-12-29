class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  def dashboard
  end

  def control_position
    position = params[:position]
    BartenderController.instance.spin_to_position! position.to_i

    redirect_to :back
  end
end
