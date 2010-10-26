module ActiveRecord
  module Acts #:nodoc:
    module List #:nodoc:
      def self.included(base)
        base.extend(ClassMethods)
      end

      # This +acts_as+ extension provides the capabilities for sorting and reordering a number of objects in a list.
      # The class that has this specified needs to have a +position+ column defined as an integer on
      # the mapped database table.
      #
      # Todo list example:
      #
      #   class TodoList < ActiveRecord::Base
      #     has_many :todo_items, :order => "position"
      #   end
      #
      #   class TodoItem < ActiveRecord::Base
      #     belongs_to :todo_list
      #     acts_as_list :scope => :todo_list
      #   end
      #
      #   todo_list.first.move_to_bottom
      #   todo_list.last.move_higher
      module ClassMethods
        # Configuration options are:
        #
        # * +column+ - specifies the column name to use for keeping the position integer (default: +position+)
        # * +scope+ - restricts what is to be considered a list. Given a symbol, it'll attach <tt>_id</tt> 
        #   (if it hasn't already been added) and use that as the foreign key restriction. It's also possible 
        #   to give it an entire string that is interpolated if you need a tighter scope than just a foreign key.
        #   Example: <tt>acts_as_list :scope => 'todo_list_id = #{todo_list_id} AND completed = 0'</tt>
        def acts_as_list(options = {})
          configuration = { :column => "position", :scope => "1 = 1" }
          configuration.update(options) if options.is_a?(Hash)

          configuration[:scope] = "#{configuration[:scope]}_id".intern if configuration[:scope].is_a?(Symbol) && configuration[:scope].to_s !~ /_id$/

          if configuration[:scope].is_a?(Symbol)
            scope_condition_method = %(
              def scope_condition
                self.class.send(:sanitize_sql_hash_for_conditions, { :#{configuration[:scope].to_s} => send(:#{configuration[:scope].to_s}) })
              end
            )
          elsif configuration[:scope].is_a?(Array)
            scope_condition_method = %(
              def scope_condition
                attrs = %w(#{configuration[:scope].join(" ")}).inject({}) do |memo,column| 
                  memo[column.intern] = send(column.intern); memo
                end
                self.class.send(:sanitize_sql_hash_for_conditions, attrs)
              end
            )
          else
            scope_condition_method = "def scope_condition() \"#{configuration[:scope]}\" end"
          end

          class_eval <<-EOV
            include ActiveRecord::Acts::List::InstanceMethods
            extend  ActiveRecord::Acts::List::ClassMethods
            
            def acts_as_list_class
              ::#{self.name}
            end

            def position_column
              '#{configuration[:column]}'
            end
            
            def position_updated_at_column
              '#{configuration[:column]}_updated_at'
            end

            #{scope_condition_method}

            #before_destroy :decrement_positions_on_lower_items
            before_create  :add_to_list_bottom
          EOV
        end
      end

      # All the methods available to a record that has had <tt>acts_as_list</tt> specified. Each method works
      # by assuming the object to be the item in the list, so <tt>chapter.move_lower</tt> would move that chapter
      # lower in the list of all chapters. Likewise, <tt>chapter.first?</tt> would return +true+ if that chapter is
      # the first in the list of all chapters.
      module InstanceMethods
        # Insert the item at the given position (defaults to the top position of 1).
        def insert_at(position = 1)
          insert_at_position(position)
        end

        # Swap positions with the next lower item, if one exists.
        def move_lower
          decrement_position
        end

        # Swap positions with the next higher item, if one exists.
        def move_higher
          increment_position
        end
        
        def list_position
          lm    = list_members
          index = lm.index(lm.find { |m| m.id == self.id })
          index == nil ? nil : index + 1
        end

        # Move to the bottom of the list. If the item is already in the list, the items below it have their
        # position adjusted accordingly.
        def move_to_bottom
          return unless in_list?
          assume_bottom_position
        end

        # Move to the top of the list. If the item is already in the list, the items above it have their
        # position adjusted accordingly.
        def move_to_top
          return unless in_list?
          assume_top_position
        end

        # Removes the item from the list.
        def remove_from_list
          if in_list?
            update_attributes(position_column => nil, position_updated_at_column => nil)
          end
        end

        # Increase the position of this item without adjusting the rest of the list.
        def increment_position
          return unless in_list?
          update_attribute_and_timestamp(position_column, self.list_position - 1)
        end

        # Decrease the position of this item without adjusting the rest of the list.
        def decrement_position
          return unless in_list?
          update_attribute_and_timestamp(position_column, self.list_position + 1)
        end

        # Return +true+ if this object is the first in the list.
        def first?
          return false unless in_list?
          list_position == 1
        end

        # Return +true+ if this object is the last in the list.
        def last?
          return false unless in_list?
          list_position == list_members.size
        end

        # The magic method that returns a list of ordered members
        def list_members
          out     = []
          members = acts_as_list_class.find(:all, :conditions => "(#{scope_condition}) AND #{position_column} IS NOT NULL", :order => "#{position_updated_at_column}")          
          
          members.each do |m|
            idx = m.send(position_column) - 1
            
            if out[idx] == nil
              out[idx] = m
            else  
              out.compact!
              out.insert(idx, m)
            end
          end

          out.compact
        end

        # Test if this record is in a list
        def in_list?
          !send(position_column).nil?
        end

        private
          def update_attribute_and_timestamp(col, val)
            update_attributes(
              col                         => val,
              position_updated_at_column  => Time.now.to_f
            )
          end
          
          def add_to_list_bottom
            self[position_column]             = list_members.size + 1
            self[position_updated_at_column]  = Time.now.to_f
          end

          # Overwrite this method to define the scope of the list changes
          def scope_condition() "1" end
        
          # Forces item to assume the bottom position in the list.
          def assume_bottom_position
            update_attribute_and_timestamp(position_column, list_members.size)
          end

          # Forces item to assume the top position in the list.
          def assume_top_position
            update_attribute_and_timestamp(position_column, 1)
          end

          def insert_at_position(position)
            update_attribute_and_timestamp(position_column, position)
          end
      end 
    end
  end
end
