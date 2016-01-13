{MACAddress, IPv4Address, Enum} = require('dripcap/type')

class UTPDecoder
  lowerLayers: -> [
    '::Ethernet::IPv4::UDP'
    '::Ethernet::IPv6::UDP'
  ]

  analyze: (packet, parentLayer) ->
    new Promise (resolve, reject) ->

      slice = parentLayer.payload
      payload = slice.apply packet.payload

      layer =
        name: 'μTP'
        aliases: [
          'uTP'
          'Micro Transport Protocol'
        ]
        namespace: parentLayer.namespace + '::uTP'
        fields: []
        attrs: {}

      assertLength = (len) ->
        throw new Error('too short frame') if payload.length < len

      try
        assertLength(20)

        firstByte = payload.readUInt8(0, true)
        version = firstByte & 0b00001111
        throw new Error('wrong uTP version') if version != 1

        table =
          0: 'ST_DATA'
          1: 'ST_FIN'
          2: 'ST_STATE'
          3: 'ST_RESET'
          4: 'ST_SYN'
        type = new Enum table, firstByte >> 4
        throw new Error('wrong uTP type') unless type.known

        layer.fields.push
          name: 'Version'
          attr: 'version'
          range: slice.slice(0, 1)
        layer.attrs.version = version

        layer.fields.push
          name: 'Type'
          attr: 'type'
          range: slice.slice(0, 1)
        layer.attrs.type = type

      catch e
        reject()
        return

      try
        extTable =
          0: 'none'
          1: 'Selective acks'

        firstExtension = new Enum extTable, payload.readUInt8(1, true)
        layer.fields.push
          name: 'First Extension'
          value: firstExtension
          range: slice.slice(1, 2)

        connectionID = payload.readUInt16BE(2, true)
        layer.fields.push
          name: 'Connection ID'
          attr: 'id'
          range: slice.slice(2, 4)
        layer.attrs.id = connectionID

        timestamp = payload.readUInt32BE(4, true)
        layer.fields.push
          name: 'Timestamp Microseconds'
          attr: 'timestamp'
          range: slice.slice(4, 8)
        layer.attrs.timestamp = timestamp

        timestampDiff = payload.readUInt32BE(8, true)
        layer.fields.push
          name: 'Timestamp Difference Microseconds'
          attr: 'timestampDiff'
          range: slice.slice(8, 12)
        layer.attrs.timestampDiff = timestampDiff

        windowSize = payload.readUInt32BE(12, true)
        layer.fields.push
          name: 'Window Size'
          attr: 'windowSize'
          range: slice.slice(12, 16)
        layer.attrs.windowSize = windowSize

        seq = payload.readUInt16BE(16, true)
        layer.fields.push
          name: 'Sequence Number'
          attr: 'seq'
          range: slice.slice(16, 18)
        layer.attrs.seq = seq

        ack = payload.readUInt16BE(18, true)
        layer.fields.push
          name: 'Acknowledgment Number'
          attr: 'ack'
          range: slice.slice(18, 20)
        layer.attrs.ack = ack

        extensions =
          name: 'Extensions'
          range: slice.slice(20, 20)
          fields: []

        offset = 20
        nextExtension = firstExtension
        while nextExtension.value != 0
          assertLength(offset + 2)
          extensionType = new Enum extTable, payload.readUInt8(offset, true)
          length = payload.readUInt8(offset + 1, true)

          assertLength(offset + 2 + length)

          if nextExtension.value == 1
            fields = []
            bytes = payload.slice(offset + 2, offset + 2 + length)
            for b, i in bytes
              fields.push
                name: "#{ack + 2 + i * 8} - #{ack + 2 + (i + 1) * 8 - 1}"
                value: b
                range: slice.slice(offset + 2 + i, offset + 2 + 1 + i)
                tag: 'utp-bitmask-value'

            extensions.fields.push
              name: "Selective acks"
              value: "#{length} bytes"
              range: slice.slice(offset + 2, offset + 2 + length)
              fields: fields
          else
            extensions.fields.push
              name: "Unknown Extension (#{nextExtension.value})"
              value: "#{length} bytes"
              range: slice.slice(offset + 2, offset + 2 + length)

          nextExtension = extensionType
          offset += 2 + length

        extensions.value = extensions.fields.map((f) -> f.name).join ', '
        layer.fields.push extensions

        layer.payload = slice.slice(offset)
        layer.fields.push
          name: 'Payload'
          value: layer.payload
          range: layer.payload

        layer.summary = "[#{type.name}] seq:#{seq} ack:#{ack}"
      catch e
        layer.error = e.message

      parentLayer.layers =
        "#{layer.namespace}": layer

      if layer.error?
        reject(parentLayer)
      else
        resolve(parentLayer)

module.exports = UTPDecoder
