class AddInvulerableToTasks < ActiveRecord::Migration
  def self.up
    add_column :tasks, :invulnerable, :boolean, :default => false
  end

  def self.down
    remove_column :tasks, :invulnerable
  end
end
