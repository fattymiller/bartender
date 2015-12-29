Rails.application.routes.draw do
  scope :development do
    post 'motor/to/:position' => 'application#control_position', as: :control_position
    post 'motor/set/:number' => 'application#set_positions', as: :set_positions
  end

  root to: 'application#dashboard'
end
