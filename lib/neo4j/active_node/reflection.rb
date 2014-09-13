module Neo4j::ActiveNode
  # A reflection contains information about an association. 
  # They are often used in connection with form builders to determine associated classes.
  # This module contains methods related to the creation and retrieval of reflections.
  module Reflection
    extend ActiveSupport::Concern

    included do
      class_attribute :reflections
      self.reflections = {}
    end

    # Adds methods to the class related to creating and retrieving reflections.
    module ClassMethods
      # @param [Symbol] macro the association type, :has_many or :has_one
      # @param [Symbol] name the association name
      # @param [Neo4j::ActiveNode::HasN::Association] association_object the association object created in the course of creating this reflection
      def create_reflection(macro, name, association_object)
        self.reflections = self.reflections.merge(name => AssociationReflection.new(macro, name, association_object))
      end

      private :create_reflection
      # @param [Symbol] association an association declared on the model
      # @return [Neo4j::ActiveNode::Reflection::AssociationReflection] of the given association
      def reflect_on_association(association)
        reflections[association.to_sym]
      end

      # Returns an array containing one reflection for each association declared in the model.
      def reflect_on_all_associations(macro = nil)
        association_reflections = reflections.values
        macro ? association_reflections.select { |reflection| reflection.macro == macro } : association_reflections
      end
    end

    # The actual reflection object that contains information about the given association.
    # These should never need to be created manually, they will always be created by declaring a :has_many or :has_one association on a model.
    class AssociationReflection
      # The name of the association
      attr_reader :name

      # The type of association, :has_many or :has_one
      attr_reader :macro

      # The association object referenced by this reflection
      attr_reader :association

      def initialize(macro, name, association)
        @macro        = macro
        @name         = name
        @association  = association
      end

      # @return [Class] The target model
      def klass
        @klass ||= class_name.constantize
      end

      # @return [String] the name of the target model
      def class_name
        @class_name ||= association.target_class.name
      end

      # @return [Class] model used by the association, if any
      def rel_klass
        @rel_klass ||= rel_class_name.constantize
      end

      # @return [String] the name of the ActiveRel class used by the association, if any
      def rel_class_name
        @rel_class_name ||= association.relationship_class.name.to_s
      end

      # @return [String] The Neo4j relationship type
      def type
        @type ||= association.relationship_type
      end

      # @return [Boolean] Returns true if association is :has_many
      def collection?
        macro == :has_many
      end

      # @return [Boolean] Always returns true at the moment for debugging
      def validate?
        # mark this as true for now until we can investigate this more
        true
        # !association.options[:validate].nil? ? association.options[:validate] : (association.autosave? || macro == :has_many)
      end

      def autosave?
        @autosave ||= association.autosave?
      end
    end
  end
end