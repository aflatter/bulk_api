class Task < ActiveRecord::Base
  validates_presence_of :title

  before_destroy :check_invulnerable

  def check_invulnerable
    return unless invulnerable
    errors.add(:base, "You can't destroy me noob!")
  end
end
