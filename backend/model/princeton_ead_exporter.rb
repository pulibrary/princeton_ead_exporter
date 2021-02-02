require 'nokogiri'
require 'securerandom'

class EADSerializer < ASpaceExport::Serializer
  serializer_for :ead

  def serialize_container(inst, xml, fragments)
    atts = {}

    sub = inst['sub_container']
    top = sub['top_container']['_resolved']

    atts[:id] = prefix_id(SecureRandom.hex)
    last_id = atts[:id]

    atts[:type] = top['type']
    text = top['indicator']

    atts[:label] = I18n.t("enumerations.instance_instance_type.#{inst['instance_type']}",
                          :default => inst['instance_type'])
    atts[:label] << " [#{top['barcode']}]" if top['barcode']

    # Add location code to the altrender attribute.
    if(collection = top["collection"])
      if(collection && collection.first)
        collection_identifier = collection.first["identifier"]
        if (location_code = top["long_display_string"].match(/\[([^\[\]]*)\], #{collection_identifier}/))
          atts[:altrender] = location_code[1]
        end
      end
    end
    if (cp = top['container_profile'])
      atts[:encodinganalog] = cp['_resolved']['url'] || cp['_resolved']['name']
    end

    xml.container(atts) {
      sanitize_mixed_content(text, xml, fragments)
    }

    (2..3).each do |n|
      atts = {}

      next unless sub["type_#{n}"]

      atts[:id] = prefix_id(SecureRandom.hex)
      atts[:parent] = last_id
      last_id = atts[:id]

      atts[:type] = sub["type_#{n}"]
      text = sub["indicator_#{n}"]

      xml.container(atts) {
        sanitize_mixed_content(text, xml, fragments)
      }
    end
  end

  def serialize_agent_notes(data, xml, fragments)
    unless data.creators_and_sources.nil?
      data.creators_and_sources.each do |link|
        agent = link['_resolved']
        published = agent['publish'] === true

        next if !published && !@include_unpublished
        notes = agent['notes'].select{ |x| x['jsonmodel_type'] == "note_bioghist" }
        notes.each do |note|
          note['type'] = 'bioghist'
          note['internal'] = false
          note['publish'] = true
          serialize_note_content(note, xml, fragments)
        end
      end
    end
  end

  def serialize_nondid_notes(data, xml, fragments)
    data.notes.each do |note|
      next if note["publish"] === false && !@include_unpublished
      next if note['internal']
      next if note['type'].nil?
      next unless data.archdesc_note_types.include?(note['type'])
      audatt = note["publish"] === false ? {:audience => 'internal'} : {}
      if note['type'] == 'legalstatus'
        xml.accessrestrict(audatt) {
          serialize_note_content(note, xml, fragments)
        }
      else
        serialize_note_content(note, xml, fragments)
      end
    end
    serialize_agent_notes(data, xml, fragments)
  end
end
