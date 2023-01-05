require 'spec_helper'

RSpec.describe AttrJson::Record do
  let(:instance) { klass.new }

  describe "store_key" do
    let(:klass) do
      Class.new do
        include AttrJson::Model

        attr_json :str_one, :string, store_key: "__str_one"
      end
    end

    it "reads attribute name from initializer" do
      instance = klass.new(str_one: "value")
      expect(instance.str_one).to eq("value")
      # attribute name in attributes
      expect(instance.attributes).to eq("str_one" => "value")
      # but store_key when serialized
      expect(instance.as_json).to eq("__str_one" => "value")
    end

    it "reads attribute name from assign_attributes" do
      instance.assign_attributes(str_one: "value")
      expect(instance.str_one).to eq("value")
      # attribute name in attributes
      expect(instance.attributes).to eq("str_one" => "value")
      # but store_key when serialized
      expect(instance.as_json).to eq("__str_one" => "value")
    end

    it "does not recognize  a store_key in assign_attributes" do
      expect {
        instance.assign_attributes("__str_one" => "value")
      }.to raise_error(ActiveModel::UnknownAttributeError)
    end
  end

  describe "validation" do
    let(:klass) do
      Class.new do
        include AttrJson::Model

        # validations need a model_name, which our anon class doens't have
        def self.model_name
          ActiveModel::Name.new(self, nil, "TestClass")
        end

        validates :str_array, presence: true
        validates :str,
          inclusion: {
            in: %w(small medium large),
            message: "%{value} is not a valid size"
          }

        attr_json :str, :string
        attr_json :str_array, :string, array: true
      end
    end

    it "has the usual validation errors" do
      instance.str = "nosize"
      expect(instance.valid?).to be false
      expect(instance.errors[:str_array]).to eq(["can't be blank"])
      expect(instance.errors[:str]).to eq(["nosize is not a valid size"])
    end
    it "valid with valid data" do
      instance.str = "small"
      instance.str_array = ["foo"]
      expect(instance.valid?).to be true
    end
  end

  describe "#dup" do
    let(:nested_class) do
      Class.new do
        include AttrJson::Model

        attr_json :str, :string
      end
    end
    let(:klass) do
      nested_class_type = nested_class.to_type
      Class.new do
        include AttrJson::Model

        attr_json :str_array, :string, array: true
        attr_json :str, :string
        attr_json :nested, nested_class_type, default: {}
      end
    end

    it "dups all nested data" do
      obj = klass.new(str: "one", str_array: ["a", "b"], nested: nested_class.new(str: "two"))
      obj_dup = obj.dup

      expect(obj_dup.str).not_to equal(obj.str)
      expect(obj_dup.str_array).not_to equal(obj.str_array)
      expect(obj_dup.str_array.first).not_to equal(obj.str_array.first)

      expect(obj_dup.nested).not_to equal(obj.nested)
      expect(obj_dup.nested.str).not_to equal(obj.nested.str)
    end
  end

  describe "#freeze" do
    let(:nested_class) do
      Class.new do
        include AttrJson::Model

        attr_json :str, :string
      end
    end
    let(:klass) do
      nested_class_type = nested_class.to_type
      Class.new do
        include AttrJson::Model

        attr_json :str_array, :string, array: true
        attr_json :str, :string
        attr_json :nested, nested_class_type, default: {}
      end
    end

    it "makes it not possible to set attributes" do
      obj = klass.new(str: "one", str_array: ["a", "b"], nested: nested_class.new(str: "two"))

      obj.freeze

      expect {
        obj.str = "foo"
      }.to raise_error(FrozenError)

      # note it's not actually deep-frozen, you can mutate attributes including
      # arrays. deep freeze could be a different feature.
    end
  end

  describe "unknown keys" do
    let(:klass) do
      Class.new do
        include AttrJson::Model

        attr_json :str_one, :string
      end
    end
    let(:attributes) { { str_one: "str", unknown_key: "foo" } }
    describe "default :raise" do
      it "raises" do
        expect { instance.assign_attributes(attributes) }.to raise_error(ActiveModel::UnknownAttributeError)
        expect { klass.new(attributes) }.to raise_error(ActiveModel::UnknownAttributeError)
      end
      it "raises on new_from_serializable" do
        expect { klass.new_from_serializable(attributes) }.to raise_error(ActiveModel::UnknownAttributeError)
      end
    end
    describe ":allow" do
      before do
        klass.attr_json_config(unknown_key: :allow)
      end
      it "allows" do
        instance.assign_attributes(attributes)
        expect(instance.str_one).to eq "str"
        expect(instance.attributes).to eq attributes.stringify_keys
        expect(instance.serializable_hash).to eq attributes.stringify_keys
      end
      it "allows on new_from_serializable" do
        instance = klass.new_from_serializable(attributes)
        expect(instance.attributes).to eq attributes.stringify_keys
      end
    end
    describe ":strip" do
      before do
        klass.attr_json_config(unknown_key: :strip)
      end
      it "strips" do
        instance.assign_attributes(attributes)
        expect(instance.str_one).to eq "str"
        expect(instance.attributes).to eq("str_one" => "str")
        expect(instance.serializable_hash).to eq("str_one" => "str")
      end
      it "strips on new_from_serializable" do
        instance = klass.new_from_serializable(attributes)
        expect(instance.attributes).to eq("str_one" => "str")
      end
    end
  end

  describe "nested model with validation" do
    let(:nested_class) do
      Class.new do
        include AttrJson::Model
        def self.model_name ; ActiveModel::Name.new(self, nil, "NestedClass") ; end
        attr_json :str, :string
        validates_presence_of :str
      end
    end
    let(:klass) do
      nested_class_type = nested_class.to_type
      Class.new do
        include AttrJson::Model
        def self.model_name ; ActiveModel::Name.new(self, nil, "Klass") ; end

        attr_json :nested, nested_class_type, default: {}
      end
    end

    it "is invalid when nested is" do
      expect(instance.valid?).to be false
      expect(instance.errors.key?(:nested)).to be true
      expect(instance.errors[:nested]).to include("is invalid")

      expect(instance.nested.errors.key?(:str))
      expect(instance.nested.errors[:str]).to include("can't be blank")

      expect(instance.errors.details[:nested].first[:value]).to be_kind_of(nested_class)
    end

    it "is valid when nested is" do
      instance.nested.str = "something"
      expect(instance.valid?).to be true
    end
  end

  describe "nested array of models with validation" do
    let(:nested_class) do
      Class.new do
        include AttrJson::Model
        def self.model_name ; ActiveModel::Name.new(self, nil, "NestedClass") ; end
        attr_json :str, :string
        validates_presence_of :str
      end
    end
    let(:klass) do
      nested_class_type = nested_class.to_type
      Class.new do
        include AttrJson::Model
        def self.model_name ; ActiveModel::Name.new(self, nil, "Klass") ; end

        attr_json :nested, nested_class_type, array: true, default: [{}]
      end
    end

    it "is invalid when nested is" do
      expect(instance.valid?).to be false
      expect(instance.errors.key?(:nested)).to be true
      expect(instance.errors[:nested]).to include("is invalid")

      expect(instance.nested.first.errors.key?(:str))
      expect(instance.nested.first.errors[:str]).to include("can't be blank")

      expect(instance.errors.details[:nested].first[:value].first).to be_kind_of(nested_class)
    end

    it "is valid when nested is" do
      instance.nested.first.str = "something"
      expect(instance.valid?).to be true
    end
  end

  describe "registered attributes" do
    let(:klass) do
      Class.new do
        include AttrJson::Model

        attr_json :str_one, :string
        attr_json "int_one", :integer
      end
    end

    it "available in registry" do
      expect(klass.attr_json_registry.attribute_names).to match([:str_one, :int_one])
    end

    it "available via .attribute_types" do
      expect(klass.attribute_types).to eq({
        "str_one" => ActiveModel::Type.lookup(:string),
        "int_one" => ActiveModel::Type.lookup(:integer),
      })
    end

    it "available via .attribute_names" do
      expect(klass.attribute_names).to match([:str_one, :int_one])
    end

    it "available via #attribute_names" do
      expect(klass.new.attribute_names).to match([:str_one, :int_one])
    end
  end

  describe "#==" do
    let(:klass) do
      Class.new do
        include AttrJson::Model

        attr_json :str_one, :string
      end
    end

    it "does not equal with different values" do
      expect(instance == klass.new(str_one: "different")).to eq(false)
    end

    it "does equal with same values" do
      expect(instance == klass.new).to eq(true)
      expect(klass.new(str_one: "value") == klass.new(str_one: "value")).to eq(true)
    end

    it "does not equal some random object" do
      expect(instance == Object.new).to eq(false)
    end
  end
end
