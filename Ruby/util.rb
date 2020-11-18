require_relative 'defines.rb'

include Paths

class Util
  def initialize(_romBytes)
    @@romBytes = _romBytes
    @@letterWidths = @@romBytes[0x19adc0..0x19ae3f]

    @@exportTable = Hash.new
    File.open(Paths::EXPORT_TBL, encoding: 'UTF-8').each {|i| @@exportTable[i.split("=")[0].to_i(16)] = i.split("=")[1].rstrip}

    @@export8x16Table = Hash.new
    File.open(Paths::EXPORT_8X16_TBL, encoding: 'UTF-8').each {|i| @@export8x16Table[i.split("=")[0].to_i(16)] = i.split("=")[1].rstrip}

    @@importTable = Hash.new
    File.open(Paths::IMPORT_TBL, encoding: 'ASCII').each {|i| @@importTable[i.split("=")[1].gsub("\n","")] = i.split("=")[0].to_i(16)}

    @@nameTable = Hash.new
    File.open(Paths::NAME_TBL, encoding: 'UTF-8').each {|i| @@nameTable[i.split("=")[0].to_i(16)] = i.split("=")[1].rstrip}

    @@opcodes = CSV.read(Paths::OPCODES_CSV, :encoding => "bom|utf-8", :headers => true, :col_sep => ";").map {|p| p.to_h}
    @@opcodes.each { |x| x["length"] = x["length"].to_i}
  end


  def self.bytesToNum(bytes,isLE = true)
    num = 0
    if isLE
      counter = 0.upto((bytes.size-1)).map {|b| b}
    else
      counter = (bytes.size-1).downto(0).map {|b| b}
    end
    bytes.size.times do |t|
      num += bytes[t] << (counter[t] * 8)
    end
    return num
  end

  def self.numToBytes(num,count,isLE)
    bytes = Array.new
    if isLE
      counter = 0.upto((count-1)).map {|b| b}
    else
      counter = (count-1).downto(0).map {|b| b}
    end
    counter.size.times do |t|
      bytes.push ((num >> (counter[t] * 8)) & 0xff)
    end
    return bytes
  end

  def self.disasmBytes(offset,count)
    #puts "%06X" % offset

    if count < 200
      stdin, stdout, stderr = Open3.popen3(Paths::VDA + ' "' + Paths::ORIGINAL_ROM + '" ' + ("0x%06x" % offset) + ' ' + ("0x%06x" % (offset + count)) )
      decData = stdout.read.to_s.split("\n").map {|s| s[36..-1].gsub("0x","$")}.join("\n")
      return decData
    else
      return ""
    end
  end

  def self.decStaticString (strBytes)
    strTextArr = String.new
    strBytes.length.times do |i|
      strTextArr += @@export8x16Table[strBytes[i]]
    end
    return strTextArr
  end

  def self.decodeString (strBytes)
    #puts strBytes.map {|m| "%02X" % m}.join(",")
    strTextArr = String.new
    tmpOffset = 0
    while tmpOffset < strBytes.size
      if strBytes[tmpOffset] == 0x01
        strTextArr += "\n"
      elsif strBytes[tmpOffset] == 0x02
        strTextArr += "\n-----\n"
      elsif strBytes[tmpOffset] == 0x03
        strTextArr += "[03]"
      elsif strBytes[tmpOffset] > 0xfc
        charCode = (strBytes[tmpOffset] << 8) + strBytes[tmpOffset+1]
        #puts "%04X" % charCode
        #strTextArr += @@exportTable[charCode]

        if @@exportTable[charCode].nil?
          strTextArr += "[%04X]" % charCode
        else
          strTextArr += @@exportTable[charCode]
        end
        tmpOffset += 1
      else
        strTextArr += @@exportTable[strBytes[tmpOffset]]
      end
      tmpOffset += 1
    end
    #puts strTextArr
    #exit
    return strTextArr
  end

  def self.calculatePtr(_dst, _base, _ptrType, _msb = false)
    if (_ptrType == 'd') ||  (_ptrType == 's')
      return _dst, 4
    elsif (_ptrType == 'r') || (_ptrType == 'f')
      dist = (_dst - _base).abs
      raise "Inaccessible pointer to %x from %x: %d" % [_dst, _base, dist] if (_dst - _base).abs > 0x8000
      return _dst - _base, 2
    elsif (_ptrType == 'n')
      res = (_dst - _base) | (_msb ? 0x8000 : 0), 2
      raise "Negative offset for n pointer: " + res[0].to_s + " pointing to " + "0x%06X" % _dst if res[0] < 0
      return res
    end
  end

  def self.opcodeDec(offset)
    currentOffset = offset
    #puts "%06X" % currentOffset
    opByte = @@romBytes[currentOffset]
    currentOp = @@opcodes[opByte]

    if opByte < 0x15 #&& !opByte.between?(0x01,0x03)
      currentOffset += 1
      opBytes = @@romBytes[currentOffset..(currentOffset+currentOp["length"]-2)] if !currentOp["length"].nil?
      opName = currentOp["name"]
      if opName == "op_inlinecode"
        currentOffset += 1 if currentOffset.modulo(2) == 1
        bytesCount = bytesToNum(@@romBytes[currentOffset..currentOffset+1],false) - 3
        currentOffset += 2
        opBytes = @@romBytes[currentOffset..currentOffset+bytesCount]
        inlineCode = opBytes
        disasmCode = disasmBytes(currentOffset,inlineCode.size)
        currentOffset += bytesCount + 1
        codeData = {:opInlineCode=>disasmCode}
      elsif opName == "op_callfunction"
        currentOffset += 1 if currentOffset.modulo(2) == 1
        bytesCount = bytesToNum(@@romBytes[currentOffset..currentOffset+1],false) - 3
        currentOffset += 2
        opBytes = @@romBytes[currentOffset..currentOffset+bytesCount]
        callOffset = bytesToNum(opBytes[0..3],false)
        callVars = opBytes[4..-1]
        currentOffset += bytesCount + 1
        codeData = {:opCallOffset=>("0x%06X" % callOffset),:opCallVars=>(callVars.map{|m| "%02X" % m}.join(" "))}
      elsif opName == "op_setportrait"
        currentOffset += (currentOp["length"]-1)
        codeData = {:opPortrait=>@@nameTable[opBytes[0]],:opPortraitPos=>opBytes[1]}
      elsif opName == "op_jump" || currentOp["name"] == "op_gosub"
        jumpOffset = bytesToNum(opBytes,false)
        currentOffset += (currentOp["length"]-1)
        codeData = {:opJumpOffset=>("0x%06X" % jumpOffset)}
      else
        codeData = {}
        currentOffset += (currentOp["length"]-1)
      end
    else
      opBytes = Array.new
      opName = "op_text"
      while @@romBytes[currentOffset] > 0x14 || @@romBytes[currentOffset].between?(1,3)
        opBytes.push @@romBytes[currentOffset]
        if @@romBytes[currentOffset] > 0xfc
          currentOffset += 1
          opBytes.push @@romBytes[currentOffset]
        end
        currentOffset += 1
      end
      decodedString = decodeString opBytes
      codeData = {:opText=>decodedString}
    end
    if opBytes.nil?
      opBytesStr = nil
    else
      opBytesStr = opBytes.map{|m| "%02X" % m}.join(" ")
    end
    fullData = {:opByte=>("0x%02X" % opByte),:opBytes=>opBytesStr,:opName=>opName,:opCallOffset=>nil,:opCallVars=>nil,:opJumpOffset=>nil,:opInlineCode=>nil,:opPortrait=>nil,:opPortraitPos=>nil,:opText=>nil}.merge(codeData)
    return [currentOffset,fullData]
  end

  def self.encodeString (strText)
    return 0x00 if strText.nil?
    strTextArr = strText.gsub(0x90.chr,"[03]").gsub(0x91.chr,"[20]").gsub(0x92.chr,"[01]").chars
    strBytesArr = Array.new
    tmpOffset = 0
    while tmpOffset < strTextArr.size
      if strTextArr[tmpOffset] == "[" && strTextArr[tmpOffset+3] == "]"
        strBytesArr.push (strTextArr[tmpOffset+1]+strTextArr[tmpOffset+2]).to_i(16)
        tmpOffset += 3
      else
        if !@@importTable[strTextArr[tmpOffset]].nil?
          strBytesArr.push(@@importTable[strTextArr[tmpOffset]])
        else
          puts ("Unknown character: " + strTextArr[tmpOffset] + ", skipping...")
          puts "\t" + strText
        end
      end
      tmpOffset += 1
    end
    #strBytesArr.push 0x00
    return strBytesArr
  end

  def self.prepareString (text,lengthLimit, isScript = true)
    if text.nil?
      return text
    end

    if text.length <= 4
      return text
    end

    linesLimit = 3

    resultString = String.new
    text.gsub!("[03]",0x90.chr)
    text.gsub!("[20]",0x91.chr)
    text.gsub! /\r\n?/, "\n"
    mBoxes = text.split("\n_\n")
    mBoxes.each do |mBox|
      stringsArr = mBox.strip.split("\n")
      lines = 1
      stringsArr.each do |string|
        string.gsub!("[01]",0x92.chr)
        tmpString = String.new
        textArr = string.split(" ")
        currLineLength = 0
        textArr.each do |word|
           wordLength = word.chars.map {|l| @@letterWidths[l.ord-0x20]}.inject(0){|sum,x| sum + x }
          tmpStringLength = tmpString.chars.map {|l| @@letterWidths[l.ord-0x20]}.inject(0){|sum,x| sum + x }
          if (tmpStringLength + wordLength + @@letterWidths[" ".ord-0x20]) > lengthLimit ||
              ((tmpStringLength > lengthLimit) && ((tmpString[-2] == ",") || (tmpString[-2] == ".") || (tmpString[-2] == "!") || (tmpString[-2] == "?")))
                resultString += tmpString.rstrip + "[01]"
                tmpString = String.new
                lines += 1
                if lines > linesLimit && isScript
                  resultString[-2] = "2"
                  lines = 1
                end
          end
          tmpString += word + " "
        end
        resultString += tmpString.rstrip + "[01]"
        lines += 1
        if lines > linesLimit && isScript
          resultString[-2] = "2"
          lines = 1
        end
      end
      resultString[-2] = "2"
    end
    if text[-3,3] == "\n_\n" && isScript
      return resultString
    else
      return resultString[0..-5]
    end

  end
end