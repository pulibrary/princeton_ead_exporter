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
        agent['notes'].each do |note|
          type = note["jsonmodel_type"].tr("note_", "")
          next unless type == 'bighis'
          audatt = published === false ? {:audience => 'internal'} : {}
          content = ASpaceExport::Utils.extract_note_text(note, @include_unpublished)
          att = {}
          xml.send('bioghist', att.merge(audatt)) {
            sanitize_mixed_content(content, xml, fragments,ASpaceExport::Utils.include_p?('bioghist'))
          }
        end
      end
    end
  end

  def serialize_did_notes(data, xml, fragments)
    data.notes.each do |note|
      next if note["publish"] === false && !@include_unpublished
      next unless data.did_note_types.include?(note['type'])

      audatt = note["publish"] === false ? {:audience => 'internal'} : {}
      content = ASpaceExport::Utils.extract_note_text(note, @include_unpublished)

      att = { :id => prefix_id(note['persistent_id']) }.reject {|k,v| v.nil? || v.empty? || v == "null" }
      att ||= {}

      case note['type']
      when 'dimensions', 'physfacet'
        att[:label] = note['label'] if note['label']
        xml.physdesc(audatt) {
          xml.send(note['type'], att) {
            sanitize_mixed_content( content, xml, fragments, ASpaceExport::Utils.include_p?(note['type'])  )
          }
        }
      when 'physdesc'
        att[:label] = note['label'] if note['label']
        xml.send(note['type'], att.merge(audatt)) {
          sanitize_mixed_content(content, xml, fragments,ASpaceExport::Utils.include_p?(note['type']))
        }
      else
        xml.send(note['type'], att.merge(audatt)) {
          sanitize_mixed_content(content, xml, fragments,ASpaceExport::Utils.include_p?(note['type']))
        }
      end
    end
    serialize_agent_notes(data, xml, fragments)
  end
end
