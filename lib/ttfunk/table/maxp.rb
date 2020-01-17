# frozen_string_literal: true

require_relative '../table'

module TTFunk
  class Table
    class Maxp < Table
      DEFAULT_MAX_COMPONENT_DEPTH = 1
      MAX_V1_TABLE_LENGTH = 34

      attr_reader :version
      attr_reader :num_glyphs
      attr_reader :max_points
      attr_reader :max_contours
      attr_reader :max_component_points
      attr_reader :max_component_contours
      attr_reader :max_zones
      attr_reader :max_twilight_points
      attr_reader :max_storage
      attr_reader :max_function_defs
      attr_reader :max_instruction_defs
      attr_reader :max_stack_elements
      attr_reader :max_size_of_instructions
      attr_reader :max_component_elements
      attr_reader :max_component_depth

      class << self
        def encode(maxp, new2old_glyph)
          ''.b.tap do |table|
            num_glyphs = new2old_glyph.length
            table << [maxp.version, num_glyphs].pack('Nn')

            if maxp.version == 0x10000
              stats = stats_for(
                maxp, glyphs_from_ids(maxp, new2old_glyph.values)
              )

              table << [
                stats[:max_points],
                stats[:max_contours],
                stats[:max_component_points],
                stats[:max_component_contours],
                # these all come from the fpgm and cvt tables, which
                # we don't support at the moment
                maxp.max_zones,
                maxp.max_twilight_points,
                maxp.max_storage,
                maxp.max_function_defs,
                maxp.max_instruction_defs,
                maxp.max_stack_elements,
                stats[:max_size_of_instructions],
                stats[:max_component_elements],
                stats[:max_component_depth]
              ].pack('n*')
            end
          end
        end

        private

        def glyphs_from_ids(maxp, glyph_ids)
          glyph_ids.each_with_object([]) do |glyph_id, ret|
            if (glyph = maxp.file.glyph_outlines.for(glyph_id))
              ret << glyph
            end
          end
        end

        def stats_for(maxp, glyphs)
          stats_for_simple(maxp, glyphs)
            .merge(stats_for_compound(maxp, glyphs))
            .each_with_object({}) do |(name, agg), ret|
              ret[name] = agg.value_or(0)
            end
        end

        def stats_for_simple(_maxp, glyphs)
          max_component_elements = Max.new
          max_points = Max.new
          max_contours = Max.new
          max_size_of_instructions = Max.new

          glyphs.each do |glyph|
            if glyph.compound?
              max_component_elements << glyph.glyph_ids.size
            else
              max_points << glyph.end_point_of_last_contour
              max_contours << glyph.number_of_contours
              max_size_of_instructions << glyph.instruction_length
            end
          end

          {
            max_component_elements: max_component_elements,
            max_points: max_points,
            max_contours: max_contours,
            max_size_of_instructions: max_size_of_instructions
          }
        end

        def stats_for_compound(maxp, glyphs)
          max_component_points = Max.new
          max_component_depth = Max.new
          max_component_contours = Max.new

          glyphs.each do |glyph|
            next unless glyph.compound?

            stats = totals_for_compound(maxp, [glyph], 0)
            max_component_points << stats[:total_points]
            max_component_depth << stats[:max_depth]
            max_component_contours << stats[:total_contours]
          end

          {
            max_component_points: max_component_points,
            max_component_depth: max_component_depth,
            max_component_contours: max_component_contours
          }
        end

        def totals_for_compound(maxp, glyphs, depth)
          total_points = Sum.new
          total_contours = Sum.new
          max_depth = Max.new(depth)

          glyphs.each do |glyph|
            if glyph.compound?
              stats = totals_for_compound(
                maxp, glyphs_from_ids(maxp, glyph.glyph_ids), depth + 1
              )

              total_points << stats[:total_points]
              total_contours << stats[:total_contours]
              max_depth << stats[:max_depth]
            else
              stats = stats_for_simple(maxp, [glyph])
              total_points << stats[:max_points]
              total_contours << stats[:max_contours]
            end
          end

          {
            total_points: total_points,
            total_contours: total_contours,
            max_depth: max_depth
          }
        end
      end

      private

      def parse!
        @version, @num_glyphs = read(6, 'Nn')

        if @version == 0x10000
          @max_points, @max_contours, @max_component_points,
            @max_component_contours, @max_zones, @max_twilight_points,
            @max_storage, @max_function_defs, @max_instruction_defs,
            @max_stack_elements, @max_size_of_instructions,
            @max_component_elements = read(26, 'Nn*')

          # a number of fonts omit these last two bytes for some reason,
          # so we have to supply a default here to prevent nils
          @max_component_depth = if length == MAX_V1_TABLE_LENGTH
                                   read(2, 'n').first
                                 else
                                   DEFAULT_MAX_COMPONENT_DEPTH
                                 end
        end
      end
    end
  end
end
