require 'spec_helper'

# Pins how each column type behaves on the Rails version under test, so a change in either
# this gem or ActiveRecord shows up here rather than in an application.
#
# Two behaviours differ between Rails 8.0 and 8.1:
#
# * Rails 8.0 deduplicates a column's default with `-default`. That is a no-op for the String
#   defaults a database adapter supplies, but it negates a numeric default and raises for
#   anything else that does not respond to `-@`. Rails 8.1 leaves the default alone.
# * A `:string` column is an untyped ActiveModel::Type::Value on Rails 8.0 and an
#   ActiveModel::Type::String on Rails 8.1, so only 8.1 casts what is assigned to it.
#
# Rails 8.0 keeps deduplicated columns in a process-wide registry keyed on name and default,
# so every default example declares a column name of its own.
rails_8_1 = ActiveRecord.version >= Gem::Version.new('8.1')

shared_examples 'a tablefree column default' do |type, default, expected|
  it "is #{expected.inspect} when declared as #{default.inspect}" do
    column_name = "#{type}_default_#{default.inspect.gsub(/\W+/, '_')}"
    stub_const('Defaulted', Class.new(ActiveRecord::Base) do
      has_no_table
      column column_name, type, default
    end)

    expect(Defaulted.new.public_send(column_name)).to eq expected
  end
end

shared_examples 'a rejected tablefree column default' do |type, default|
  it "raises when declared as #{default.inspect}" do
    column_name = "#{type}_default_#{default.inspect.gsub(/\W+/, '_')}"

    expect do
      stub_const('Defaulted', Class.new(ActiveRecord::Base) do
        has_no_table
        column column_name, type, default
      end)
      Defaulted.new
    end.to raise_error(NoMethodError, /-@/)
  end
end

shared_examples 'a tablefree column cast' do |attribute, input, expected, predicate|
  describe "assigning #{input.inspect}" do
    subject(:part) { Part.new(attribute => input) }

    it "reads back #{expected.inspect}" do
      expect(part.public_send(attribute)).to eq expected
    end

    it "answers #{predicate} to the predicate" do
      expect(part.public_send("#{attribute}?")).to be predicate
    end

    it 'casts the same way through nested attributes' do
      widget = Widget.new(parts_attributes: { '0' => { attribute => input } })

      expect(widget.parts.first.public_send(attribute)).to eq expected
    end
  end
end

describe 'Tablefree column types' do
  before do
    stub_const('Widget', Class.new(ActiveRecord::Base) do
      has_no_table
      column :id, :integer
      has_many :parts
      accepts_nested_attributes_for :parts
    end)
    stub_const('Part', Class.new(ActiveRecord::Base) do
      has_no_table
      belongs_to :widget
      column :widget_id, :integer
      column :quantity, :integer
      column :label, :string
      column :notes, :text
      column :fragile, :boolean
      column :shipped_at, :date_time
      column :payload, :value
      column :quantity_with_default, :integer, '7'
      column :label_with_default, :string, 'spare'
      column :notes_with_default, :text, 'none'
      column :fragile_with_default, :boolean, 'true'
      column :shipped_at_with_default, :date_time, '2026-01-02 03:04:05'
      column :payload_with_default, :value, 'raw'
    end)
  end

  describe 'attributes a nested record does not submit' do
    subject(:part) { Widget.new(parts_attributes: { '0' => { quantity: '3' } }).parts.first }

    it 'keep their declared defaults' do
      expect(part).to have_attributes(
        quantity: 3,
        quantity_with_default: 7,
        label_with_default: 'spare',
        notes_with_default: 'none',
        fragile_with_default: true,
        shipped_at_with_default: Time.utc(2026, 1, 2, 3, 4, 5),
        payload_with_default: 'raw'
      )
    end

    it 'stay nil without a declared default' do
      expect(part).to have_attributes(label: nil, notes: nil, fragile: nil, shipped_at: nil, payload: nil)
    end
  end

  describe ':integer' do
    it 'is an integer type' do
      expect(Part.type_for_attribute('quantity')).to be_an_instance_of(ActiveModel::Type::Integer)
      expect(Part.columns_hash['quantity']).to have_attributes(type: :integer, sql_type: 'integer', null: true)
    end

    describe 'default' do
      it_behaves_like 'a tablefree column default', :integer, nil, nil
      it_behaves_like 'a tablefree column default', :integer, '1', 1
      it_behaves_like 'a tablefree column default', :integer, '-1', -1
      it_behaves_like 'a tablefree column default', :integer, '5', 5
      it_behaves_like 'a tablefree column default', :integer, 'abc', 0
      it_behaves_like 'a tablefree column default', :integer, 0, 0
      it_behaves_like 'a tablefree column default', :integer, 1, (rails_8_1 ? 1 : -1)
      it_behaves_like 'a tablefree column default', :integer, -1, (rails_8_1 ? -1 : 1)
      it_behaves_like 'a tablefree column default', :integer, 5, (rails_8_1 ? 5 : -5)
    end

    it_behaves_like 'a tablefree column cast', :quantity, '1', 1, true
    it_behaves_like 'a tablefree column cast', :quantity, '0', 0, false
    it_behaves_like 'a tablefree column cast', :quantity, '', nil, false
    it_behaves_like 'a tablefree column cast', :quantity, ' ', nil, false
    it_behaves_like 'a tablefree column cast', :quantity, nil, nil, false
    it_behaves_like 'a tablefree column cast', :quantity, '12abc', 12, true
    it_behaves_like 'a tablefree column cast', :quantity, 'abc', 0, false
    it_behaves_like 'a tablefree column cast', :quantity, 1.9, 1, true
    it_behaves_like 'a tablefree column cast', :quantity, true, 1, true
    it_behaves_like 'a tablefree column cast', :quantity, false, 0, false
    it_behaves_like 'a tablefree column cast', :quantity, [1], nil, false
  end

  describe ':string' do
    it "is #{rails_8_1 ? 'a string' : 'an untyped value'} type" do
      expect(Part.type_for_attribute('label'))
        .to be_an_instance_of(rails_8_1 ? ActiveModel::Type::String : ActiveModel::Type::Value)
      expect(Part.columns_hash['label']).to have_attributes(type: :string, sql_type: 'string', null: true)
    end

    describe 'default' do
      it_behaves_like 'a tablefree column default', :string, nil, nil
      it_behaves_like 'a tablefree column default', :string, 'abc', 'abc'
      it_behaves_like 'a tablefree column default', :string, '', ''
      it_behaves_like 'a tablefree column default', :string, 5, (rails_8_1 ? '5' : -5)

      if rails_8_1
        it_behaves_like 'a tablefree column default', :string, :sym, 'sym'
      else
        it_behaves_like 'a rejected tablefree column default', :string, :sym
      end
    end

    it_behaves_like 'a tablefree column cast', :label, 'abc', 'abc', true
    it_behaves_like 'a tablefree column cast', :label, '', '', false
    it_behaves_like 'a tablefree column cast', :label, nil, nil, false
    it_behaves_like 'a tablefree column cast', :label, 5, (rails_8_1 ? '5' : 5), true
    it_behaves_like 'a tablefree column cast', :label, 1.5, (rails_8_1 ? '1.5' : 1.5), true
    it_behaves_like 'a tablefree column cast', :label, :sym, (rails_8_1 ? 'sym' : :sym), true
    it_behaves_like 'a tablefree column cast', :label, true, (rails_8_1 ? 't' : true), true
    it_behaves_like 'a tablefree column cast', :label, false, (rails_8_1 ? 'f' : false), rails_8_1
    it_behaves_like 'a tablefree column cast', :label, [1], (rails_8_1 ? '[1]' : [1]), true
  end

  describe ':text' do
    it 'is a text type' do
      expect(Part.type_for_attribute('notes')).to be_an_instance_of(ActiveRecord::Type::Text)
      expect(Part.columns_hash['notes']).to have_attributes(type: :text, sql_type: 'text', null: true)
    end

    describe 'default' do
      it_behaves_like 'a tablefree column default', :text, nil, nil
      it_behaves_like 'a tablefree column default', :text, 'abc', 'abc'
      it_behaves_like 'a tablefree column default', :text, 5, (rails_8_1 ? '5' : '-5')
    end

    it_behaves_like 'a tablefree column cast', :notes, 'abc', 'abc', true
    it_behaves_like 'a tablefree column cast', :notes, '', '', false
    it_behaves_like 'a tablefree column cast', :notes, nil, nil, false
    it_behaves_like 'a tablefree column cast', :notes, 5, '5', true
    it_behaves_like 'a tablefree column cast', :notes, :sym, 'sym', true
    it_behaves_like 'a tablefree column cast', :notes, true, 't', true
  end

  describe ':boolean' do
    it 'is a boolean type' do
      expect(Part.type_for_attribute('fragile')).to be_an_instance_of(ActiveModel::Type::Boolean)
      expect(Part.columns_hash['fragile']).to have_attributes(type: :boolean, sql_type: 'boolean', null: true)
    end

    describe 'default' do
      it_behaves_like 'a tablefree column default', :boolean, nil, nil
      it_behaves_like 'a tablefree column default', :boolean, 'true', true
      it_behaves_like 'a tablefree column default', :boolean, 'false', false
      it_behaves_like 'a tablefree column default', :boolean, '1', true
      it_behaves_like 'a tablefree column default', :boolean, '0', false
      it_behaves_like 'a tablefree column default', :boolean, 1, true
      it_behaves_like 'a tablefree column default', :boolean, 0, false
      it_behaves_like 'a tablefree column default', :boolean, false, false

      if rails_8_1
        it_behaves_like 'a tablefree column default', :boolean, true, true
      else
        it_behaves_like 'a rejected tablefree column default', :boolean, true
      end
    end

    it_behaves_like 'a tablefree column cast', :fragile, '1', true, true
    it_behaves_like 'a tablefree column cast', :fragile, '0', false, false
    it_behaves_like 'a tablefree column cast', :fragile, '', nil, false
    it_behaves_like 'a tablefree column cast', :fragile, nil, nil, false
    it_behaves_like 'a tablefree column cast', :fragile, 'true', true, true
    it_behaves_like 'a tablefree column cast', :fragile, 'false', false, false
    it_behaves_like 'a tablefree column cast', :fragile, 't', true, true
    it_behaves_like 'a tablefree column cast', :fragile, 'f', false, false
    it_behaves_like 'a tablefree column cast', :fragile, 'on', true, true
    it_behaves_like 'a tablefree column cast', :fragile, 'off', false, false
    it_behaves_like 'a tablefree column cast', :fragile, 'abc', true, true
    it_behaves_like 'a tablefree column cast', :fragile, 1, true, true
    it_behaves_like 'a tablefree column cast', :fragile, 0, false, false
    it_behaves_like 'a tablefree column cast', :fragile, true, true, true
    it_behaves_like 'a tablefree column cast', :fragile, false, false, false
  end

  describe ':date_time' do
    it 'is a datetime type' do
      expect(Part.type_for_attribute('shipped_at')).to be_an_instance_of(ActiveRecord::Type::DateTime)
      expect(Part.columns_hash['shipped_at']).to have_attributes(type: :datetime, sql_type: 'datetime', null: true)
    end

    describe 'default' do
      it_behaves_like 'a tablefree column default', :date_time, nil, nil
      it_behaves_like 'a tablefree column default', :date_time, '2026-01-02 03:04:05', Time.utc(2026, 1, 2, 3, 4, 5)

      if rails_8_1
        it_behaves_like 'a tablefree column default', :date_time, Time.utc(2026, 1, 2), Time.utc(2026, 1, 2)
      else
        it_behaves_like 'a rejected tablefree column default', :date_time, Time.utc(2026, 1, 2)
      end
    end

    it_behaves_like 'a tablefree column cast', :shipped_at, '2026-01-02 03:04:05', Time.utc(2026, 1, 2, 3, 4, 5), true
    it_behaves_like 'a tablefree column cast', :shipped_at, '2026-01-02', Time.utc(2026, 1, 2), true
    it_behaves_like 'a tablefree column cast', :shipped_at, '', nil, false
    it_behaves_like 'a tablefree column cast', :shipped_at, nil, nil, false
    it_behaves_like 'a tablefree column cast', :shipped_at, 'abc', nil, false
    it_behaves_like 'a tablefree column cast', :shipped_at, Time.utc(2026, 1, 2, 3, 4, 5), Time.utc(2026, 1, 2, 3, 4, 5), true
    it_behaves_like 'a tablefree column cast', :shipped_at, Date.new(2026, 1, 2), Date.new(2026, 1, 2), true
  end

  describe ':value' do
    it 'is an untyped value type' do
      expect(Part.type_for_attribute('payload')).to be_an_instance_of(ActiveModel::Type::Value)
      expect(Part.columns_hash['payload']).to have_attributes(type: nil, sql_type: '', null: true)
    end

    describe 'default' do
      it_behaves_like 'a tablefree column default', :value, nil, nil
      it_behaves_like 'a tablefree column default', :value, 'x', 'x'
      it_behaves_like 'a tablefree column default', :value, 5, (rails_8_1 ? 5 : -5)

      if rails_8_1
        it_behaves_like 'a tablefree column default', :value, [1, 2], [1, 2]
        it_behaves_like 'a tablefree column default', :value, { 'a' => 1 }, { 'a' => 1 }
        it_behaves_like 'a tablefree column default', :value, :sym, :sym
        it_behaves_like 'a tablefree column default', :value, true, true
      else
        it_behaves_like 'a rejected tablefree column default', :value, [1, 2]
        it_behaves_like 'a rejected tablefree column default', :value, { 'a' => 1 }
        it_behaves_like 'a rejected tablefree column default', :value, :sym
        it_behaves_like 'a rejected tablefree column default', :value, true
      end
    end

    it_behaves_like 'a tablefree column cast', :payload, 'abc', 'abc', true
    it_behaves_like 'a tablefree column cast', :payload, '', '', false
    it_behaves_like 'a tablefree column cast', :payload, nil, nil, false
    it_behaves_like 'a tablefree column cast', :payload, 5, 5, true
    it_behaves_like 'a tablefree column cast', :payload, :sym, :sym, true
    it_behaves_like 'a tablefree column cast', :payload, [1, { 'a' => 2 }], [1, { 'a' => 2 }], true
    it_behaves_like 'a tablefree column cast', :payload, { 'a' => 1 }, { 'a' => 1 }, true
  end
end
