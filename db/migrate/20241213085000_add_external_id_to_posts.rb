# frozen_string_literal: true

class AddExternalIdToPosts < ActiveRecord::Migration[7.2]
  def change
    add_column :posts, :external_id, :string, null: true
    add_index :posts, :external_id, unique: true, where: "external_id IS NOT NULL"
  end
end
