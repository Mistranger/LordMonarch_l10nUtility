require_relative 'defines.rb'
require_relative 'util.rb'

require 'sqlite3'
require "chunky_png"

# Open the original ROM for reading
@romBytes = IO.binread(Paths::ORIGINAL_ROM).bytes if File.exist?(Paths::ORIGINAL_ROM)
@romBytes.freeze
# Create patched ROM file for writing
@patchedRom = IO.binread(Paths::ORIGINAL_ROM).bytes if File.exist?(Paths::ORIGINAL_ROM)

module Configuration
  Mode = "full"                                # (see below)
  VerboseOutput = true                         # Debug messages on/off
  CreateTranslationTemplate = false            # Creates empty template DB with translation strings
  RepackResourses = false                      # Re-encodes all encoded data (takes a lot of time)
end

# DB used to store in-game script structure
if Configuration::Mode == "full"
  @db = SQLite3::Database.new(':memory:')
elsif Configuration::Mode == "export"
  FileUtils.rm_f(Paths::EXPORT_DB)
  @db = SQLite3::Database.new Paths::EXPORT_DB
elsif Configuration::Mode == "import"
  @fileDB = SQLite3::Database.new(Paths::EXPORT_DB)
  @db = SQLite3::Database.new(':memory:')
  b = SQLite3::Backup.new(@db, 'main', @fileDB, 'main')
  begin
    b.step(1) #=> OK or DONE
  end while b.remaining > 0
  b.finish
end

# for debug
# FileUtils.rm_f(Paths::EXPORT_DB)
# @db = SQLite3::Database.new Paths::EXPORT_DB

def debugPrint(_args)
  if Configuration::VerboseOutput
    p _args
  end
end

# add method to convert Array of ints to Array of ranges (used for free space calculation)
class Array
  def to_ranges
    array = self.compact.uniq.sort
    ranges = []
    if !array.empty?
      # Initialize the left and right endpoints of the range
      left, right = self.first, nil
      array.each do |obj|
        # If the right endpoint is set and obj is not equal to right's successor
        # then we need to create a range.
        if right && obj != right.succ
          ranges << Range.new(left,right)
          left = obj
        end
        right = obj
      end
      ranges << Range.new(left,right)
    end
    ranges
  end
end

# Class responsible for ROM game script extraction
class DataExporter

  # Parameters
  # _db - database used for parsing
  # _dataFile - CSV with pointers representing ROM structure
  # _romBytes - actual ROM data

  def initialize(_db, _dataFile, _romBytes)
    @db = _db

    # Holds processed addresses
    @tblPtrs = Hash.new
    # Hold information about processed script opcodes
    @opcodePtrs = Hash.new
    # Array with strings that should be translated, populated while parsing
    @translation = Array.new
    # Array with script occupied ROM memory, populated while parsing
    @freeSpaceArr = Array.new
    # This hash holds all static strings drawn with 8x16 characters
    @staticStrings = Hash.new

    # special hashes used to store script relocation information - inline LEAs, subrouting addresses and 0x007184 extra data
    @leas = Hash.new
    @subs = Hash.new
    @extra = Hash.new
    @leaCount = 0
    @subCount = 0
    @extraCount = 0

    # Global counters (used mostly to populate DB primary key IDs)
    @tableCount = 0
    @linkedScriptCount = 0
    @textCount = 0
    @opCount = 0

    # Creates SQLite database in memory with schema
    self.createDatabase()

    @romBytes = _romBytes
    # read file with ROM pointer information
    @ptrs = CSV.read(_dataFile, :encoding => "utf-8", :headers => true, :col_sep => ";").map {|p| p.to_h}

    # Adjust table counter
    self.getTableCount()
  end

  # Main data extraction procedure
  # Parses all pointers in pointer CSV adding new ones while parsing and populates DB tables
  # After opcode extraction is complete, it updates tOpLinks and tOpExtra tables to store relocation information
  def exportData()
    self.parsePtrs()
    self.updateDatabaseLinks()
    self.assignGroups()
    self.compactFreeSpace()

    self.exportStaticStrings()
    self.exportTranslation()
  end

  def parsePtrs
    @ptrs.each do |ptr|
      debugPrint "Processing " + ptr["name"] + " at " + ptr["tableptr"]

      # Dereference table pointer
      tableAddr = dereferenceTable(ptr)
      parseOnly = ptr["parseOnly"]

      if parseOnly.nil?
        @db.execute("INSERT INTO tData (mTableID, mTablePtr, mPtrType, mStructure, mCount, mPtr, mSpecial) VALUES (?, ?, ?, ?, ?, ?, ?)", [
            ptr["name"],
            ptr["tableptr"],
            ptr["ptrType"],
            ptr["structure"],
            ptr["count"],
            "0x%06X" % tableAddr,
            ptr["specialHandler"]
        ])
      end

      ptr["count"].to_i.times do |pt|
        ptrStructure = ptr["structure"].split(",")

        # Get script effective address in ROM
        ptrOffset, ptrAddress, skip, msb = getScriptAddr(ptr, tableAddr, pt, ptrStructure)

        # Generate table line stub
        linePrefix = {
            :opPtrTable => ptr["name"],
            :opPtrTablePtrType => ptr["ptrType"],
            :opPtrStructure => ptr["structure"],
            :opPtrComment => ptr["comment"],
            :opPtrSpecial => ptr["specialHandler"],
            :opPtrTablePtr => ("0x%06X" % tableAddr),
            :opPtrOffset => ("0x%06X" % ptrOffset),
            :opPtrData => ("0x%06X" % ptrAddress),
            :opIsScript => ptr["isScript"],
            :opLineWidth => ptr["lineWidth"],
        }

        toProcess = false
        if skip or (ptrOffset == ptrAddress and ptrStructure[1] != 's')
          opcodeNum = -1
        elsif !@opcodePtrs[ptrAddress].nil?
          opcodeNum = @opcodePtrs[ptrAddress][:mID]
        else
          @tblPtrs[ptrAddress] = true
          opcodeNum = @opCount
          toProcess = true
        end
        if parseOnly.nil?
          @db.execute("INSERT INTO tPointers (mTable, mPtr, mPtrRef, mReference, mIndex, mMinAddr, mMaxAddr, mMSB, mIsScript) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", [
              ptr["name"],
              "0x%06X" % ptrOffset,
              "0x%06X" % ptrAddress,
              opcodeNum,
              pt,
              ptr["minAddr"],
              ptr["maxAddr"],
              msb.to_s,
              ptr["isScript"],
          ])
        end
        if toProcess
          processScript(linePrefix, ptrAddress)
        end
      end
    end
  end

  # Used to count new tables added while parsing ROM
  def getTableCount()
    @tableCount = @ptrs.count {|it| it["name"].include?("tbl")}
  end

  # Pointer dereferencing procedures
  def refDirectPointer(_addr)
    Util.bytesToNum(@romBytes[_addr.._addr+3], false)
  end

  def refRelPointer(_base, _addr, _msb = false)
    addrBytes = @romBytes[_addr.._addr+1]
    if addrBytes[0] >= 0x80 && _msb
      addrBytes[0] -= 0x80
    else
      _msb = false
    end

    res = _base + Util.bytesToNum(addrBytes, false)
    if addrBytes[0] >= 0x80 && !_msb
      res -= 0x10000
    end
    return res, _msb
  end

  def refRelCurPointer(_base)
    _base + Util.bytesToNum(@romBytes[_base.._base+1], false)
  end

  # Add table referenced by other pointer to processing list
  def addRefTable(_tableAddr, _structure, _count, _lineWidth = 280)
    if @tblPtrs[_tableAddr].nil?
      @tblPtrs[_tableAddr] = true
      @tableCount += 1
      @ptrs.push({
        "name"=>("tbl%03d" % @tableCount),
        "tableptr"=>"0x%06X" % _tableAddr,
        "ptrType"=>"s",
        "structure"=>_structure,
        "count"=>_count,
        "isScript"=>"true",
        "lineWidth"=>_lineWidth,
        "comment"=>"Referenced table"
      })
    end
  end

  # Gets table address from pointer
  # _ptr - table pointer
  def dereferenceTable(_ptr)
    # Dereference pointer
    tablePtrAddr = _ptr["tableptr"].to_i(16)
    tablePtrType = _ptr["ptrType"]
    if tablePtrType == "d" # direct pointer
      tableAddr = refDirectPointer(tablePtrAddr)
    elsif tablePtrType == "r" # PC relative pointer
      tableAddr, msb = refRelPointer(tablePtrAddr, tablePtrAddr)
    elsif tablePtrType == "s" # not a table
      tableAddr = tablePtrAddr
    else
      raise "Wrong table pointer type: " + tablePtrType
    end
    return tableAddr
  end

  # Special handling for Battle Scripts table
  def processSpecial3(_addr, _ptnum)
    # A Battle Scripts table entity starts with word descripting script count
    ptrCount = Util.bytesToNum(@romBytes[_addr.._addr+1], false)
    if ptrCount == 0xFFFF # no scripts
      return
    end
    ptrCount += 1
    offScript = _addr + 10
    ptrCount.times do |i|
      @ptrs.push({
                     "name"=>("scr%03d" % @linkedScriptCount),
                     "tableptr"=>"0x%06X" % offScript,
                     "ptrType"=>"s",
                     "structure"=>"2,r",
                     "count"=>1,
                     "isScript"=>"true",
                     "lineWidth"=>Const::LineWidth_InBattle,
                     "comment"=>("Battle Script (%d-%d)" % [_ptnum / 4 + 1, _ptnum % 4 + 1] )
                 })
      @linkedScriptCount += 1
      offScript += 12
    end
  end

  # Get script effective address in ROM
  def getScriptAddr(_ptr, _tableAddr, _ptnum, _ptrStructure)
    structSize = _ptrStructure[0].to_i
    ptrType = _ptrStructure[1]
    skip = false
    msb = false

    ptrSize = ptrType == "d" or ptrType == "s" ? 4 : 2
    ptrOffset = _tableAddr + _ptnum*structSize

    if ptrType == "d" # direct pointer
      ptrAddress = refDirectPointer(ptrOffset)
    elsif ptrType == "r" # relative pointer
      ptrAddress, msb = refRelPointer(_tableAddr, ptrOffset)
    elsif ptrType == "n" # relative pointer with flag at MSB
      ptrAddress, msb = refRelPointer(_tableAddr, ptrOffset, true)
    elsif ptrType == "f" # relative pointer with relative base
      ptrAddress = refRelCurPointer(ptrOffset)
    elsif ptrType == "s" # no pointer
      ptrAddress = ptrOffset
    else
      raise "Wrong table pointer type"
    end

    if _ptr["specialHandler"] == "special1" # Help Choices table
      if _ptnum % 4 == 2 # every 3rd item is referencing itself
        return ptrOffset, ptrAddress, true, false
      elsif _ptnum % 4 == 3 # every 4rd item points to additional table
        newTableSize = _ptrStructure[2]
        addRefTable(ptrAddress, "2,f",newTableSize, _ptr["lineWidth"])
        skip = true
      end
    elsif _ptr["specialHandler"] == "special2" # Skirmish Strings table
      # a table thaat points to another table
      newTableSize = _ptrStructure[2 + _ptnum]
      addRefTable(ptrAddress, "2,r", newTableSize, _ptr["lineWidth"])
      skip = true
    elsif _ptr["specialHandler"] == "special3" # Battle Scripts table
      processSpecial3(ptrAddress, _ptnum)
      skip = true
    end

    return ptrOffset, ptrAddress, skip, msb
  end

  # Creates SQLite DB and builds its schema
  def createDatabase()
    tData = @db.execute <<-SQL
      CREATE TABLE "tData" (
        "mTableID"	TEXT NOT NULL UNIQUE,
        "mTablePtr"	INTEGER NOT NULL,
        "mPtrType"	TEXT NOT NULL,
        "mStructure"	TEXT NOT NULL,
        "mCount"	INTEGER NOT NULL,
        "mPtr"	TEXT NOT NULL,
        "mSpecial"	TEXT,
        PRIMARY KEY("mTableID")
      );
    SQL
    tPointers = @db.execute <<-SQL
      CREATE TABLE "tPointers" (
        "mID"	INTEGER NOT NULL UNIQUE,
        "mTable"	TEXT NOT NULL,
        "mPtr"	TEXT NOT NULL,
        "mPtrRef"	TEXT NOT NULL,
        "mReference"	INTEGER DEFAULT -1,
        "mIndex"	INTEGER NOT NULL DEFAULT 0,
        "mMinAddr"	TEXT,
        "mMaxAddr"	TEXT,
        "mMSB"	TEXT DEFAULT 'false',
        "mIsScript"	TEXT NOT NULL DEFAULT 'true',
        FOREIGN KEY("mTable") REFERENCES "tData"("mTableID"),
        PRIMARY KEY("mID" AUTOINCREMENT)
      );
    SQL

    tOpcodes = @db.execute <<-SQL
      CREATE TABLE "tOpcodes" (
        "mID"	INTEGER NOT NULL UNIQUE,
        "mOpAddr"	TEXT NOT NULL UNIQUE,
        "mGroup"	INTEGER NOT NULL DEFAULT 0,
        "mLength"	INTEGER NOT NULL,
        "mByte"	TEXT NOT NULL,
        "mParams"	TEXT,
        "mName"	TEXT NOT NULL,
        "mTextID"	INTEGER DEFAULT -1,
        "mTranslation"	TEXT,
        "mExPortrait"	INTEGER,
        "mExPortraitPos"	INTEGER,
        "mExInlineCode"	TEXT,
        "mExJumpOffset"	INTEGER,
        "mExCallOffset"	INTEGER,
        "mExCallVars"	TEXT,
        "mIsScript"	TEXT NOT NULL DEFAULT 'true',
        "mLineWidth"	INTEGER DEFAULT 280,
        PRIMARY KEY("mID" AUTOINCREMENT),
        FOREIGN KEY("mExJumpOffset") REFERENCES "tOpcodes"("mID")
      );
    SQL
    tOpLinks = @db.execute <<-SQL
      CREATE TABLE "tOpLinks" (
        "mID"	INTEGER NOT NULL UNIQUE,
        "mOpcode"	INTEGER NOT NULL,
        "mReference"	INTEGER,
        "mType"	TEXT NOT NULL,
        "mLeaOffset"	TEXT,
        "mRefTable"	TEXT,
        FOREIGN KEY("mOpcode") REFERENCES "tOpcodes"("mID"),
        FOREIGN KEY("mReference") REFERENCES "tOpcodes"("mID"),
        PRIMARY KEY("mID" AUTOINCREMENT)
      );
    SQL

    tOpExtra = @db.execute <<-SQL
      CREATE TABLE "tOpExtra" (
        "mID"	INTEGER NOT NULL UNIQUE,
        "mOpCode"	INTEGER NOT NULL UNIQUE,
        "mPos"	TEXT NOT NULL,
        "mBytes"	TEXT NOT NULL,
        "mPtrs"	TEXT NOT NULL,
        PRIMARY KEY("mID" AUTOINCREMENT),
        FOREIGN KEY("mOpCode") REFERENCES "tOpcodes"("mID")
      );
    SQL

    if Configuration::CreateTranslationTemplate
      FileUtils.rm_f(Paths::TRANSLATION_TEMPLATE_DB)
      @t10nDB = SQLite3::Database.new(Paths::TRANSLATION_TEMPLATE_DB)
      tTranslation = @t10nDB.execute <<-SQL
        CREATE TABLE "tTranslation" (
          "mID"	INTEGER NOT NULL UNIQUE,
          "mOpAddr"	TEXT NOT NULL UNIQUE,
          "mASCII"	TEXT NOT NULL,
          "mText"	TEXT NOT NULL,
          "mTranslation"	TEXT DEFAULT "",
          PRIMARY KEY("mID" AUTOINCREMENT)
        );
      SQL

      tStaticStrings = @t10nDB.execute <<-SQL
        CREATE TABLE "tStaticStrings" (
          "mID"	INTEGER NOT NULL UNIQUE,
          "mAddr"	TEXT NOT NULL UNIQUE,
          "mText"	TEXT NOT NULL,
          "mStrLimit"	INTEGER,
          "mTranslation"	TEXT DEFAULT "",
          "mPtrAddr"	TEXT NOT NULL,
	        "mPtrType"	TEXT NOT NULL,
          PRIMARY KEY("mID" AUTOINCREMENT)
        );
      SQL
    end
  end

  def processScript(_linePrefix, _scriptAddr)
    @currentOffset = @prevOffset = _scriptAddr
    menuStub = 0

    # debugPrint "Processing script at " + "0x%06X" % _scriptAddr

    while @currentOffset < Const::ROM_Size
      lineHash = _linePrefix.merge({:opCodeOffset=>("0x%06X" % @currentOffset),
                                    :opTextID => -1,
                                    :opID=>@opCount})

      if (!@opcodePtrs[@currentOffset].nil?)
        debugPrint "Data at " + "0x%06X" % @currentOffset + " has been already decoded!"
        break
      end

      # decode opcode and build a hash containing all acquired data
      cmdDecodeArr = Util.opcodeDec(@currentOffset)
      @prevOffset = @currentOffset
      @currentOffset = cmdDecodeArr[0]
      cmdDecode = cmdDecodeArr[1]
      opLength = @currentOffset - @prevOffset
      @opcodePtrs[@prevOffset] = {:mID => @opCount, :mLength => opLength}

      # process special opcodes
      if cmdDecode[:opName] == "op_inlinecode"
        script_Inline(cmdDecode, lineHash)
      end
      if cmdDecode[:opName] == "op_jump" || cmdDecode[:opName] == "op_gosub"
        script_JumpGosub(cmdDecode, lineHash)
      end
      if cmdDecode[:opName] == "op_callfunction"
        if cmdDecode[:opCallOffset] == "0x007184"
          script_ExtraFor7184(cmdDecode, lineHash)
        end
      end
      if cmdDecode[:opName] == "op_text"
        # Push text to translation lists
        @translation.push [@textCount, lineHash[:opCodeOffset], cmdDecode[:opBytes].split(" ").map{|b| b.to_i(16).clamp(64, 122)}.pack('c*'), cmdDecode[:opText], nil]
        lineHash[:opTextID] = @textCount
        @textCount += 1
      end
      if cmdDecode[:opName] == "op_menu_create"
        menuStub = 1
      end

      if cmdDecode[:opName] == "op_exit" && menuStub == 1
        menuStub = 0
        cmdDecode[:opName] = "op_menu_exit"
      end

      script_populate_tOpcodes(cmdDecode, lineHash, opLength)

      if (cmdDecode[:opName] == "op_exit" && menuStub == 0) || cmdDecode[:opName] == "op_jump"
        break
      end
    end

    # Get information about opcode used space
    if (@currentOffset != _scriptAddr)
      usedSpace = (_scriptAddr..@currentOffset).to_a
      @freeSpaceArr |= usedSpace
    end
  end

  def script_populate_tOpcodes(cmdDecode, lineHash, opLength)
    @db.execute("INSERT INTO tOpcodes (mID, mOpAddr, mLength, mByte, mParams, mName, mTextID, mTranslation, mExPortrait,
        mExPortraitPos, mExInlineCode, mExJumpOffset, mExCallOffset, mExCallVars, mIsScript, mLineWidth)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [
        @opCount,
        "0x%06X" % @prevOffset,
        opLength,
        cmdDecode[:opByte],
        cmdDecode[:opBytes],
        cmdDecode[:opName],
        lineHash[:opTextID],
        "",
        cmdDecode[:opPortrait],
        cmdDecode[:opPortraitPos],
        cmdDecode[:opInlineCode],
        nil,
        cmdDecode[:opCallOffset],
        cmdDecode[:opCallVars],
        lineHash[:opIsScript],
        lineHash[:opLineWidth],
    ])
    @opCount += 1
  end

  def script_ExtraFor7184(cmdDecode, lineHash)
    linkOffset = Util.bytesToNum((cmdDecode[:opCallVars].split(" ").map { |b| b.to_i(16) }), false)
    linkCount = Util.bytesToNum(@romBytes[linkOffset..linkOffset + 1], false) + 1
    linkPtrs = []
    scrOffset = linkOffset + 2
    linkCount.times do |link|
      scrOffset += 2
      linkPtrs.push "0x%06X" % (Util.bytesToNum(@romBytes[scrOffset..scrOffset + 3], false))
      scrOffset = scrOffset + 4
      if (linkCount > 0)
        scrOffset += 2
      end

      @ptrs.push ({"name" => ("ext%03d" % @extraCount),
                   "tableptr" => "0x%06X" % linkPtrs.last,
                   "ptrType" => "s",
                   "structure" => "4,s",
                   "count" => 1,
                   "comment" => "Unk",
                   "isScript" => "true",
                   "lineWidth" => lineHash[:opLineWidth],
                   "parseOnly" => "true"})
      @extraCount += 1
    end
    @db.execute("INSERT INTO tOpExtra (mOpcode, mPos, mBytes, mPtrs) VALUES (?, ?, ?, ?)", [
        @opCount,
        "0x%06X" % linkOffset,
        @romBytes[linkOffset..scrOffset - 1].to_s,
        linkPtrs.to_s
    ])
    usedSpace = (linkOffset..scrOffset - 1).to_a
    @freeSpaceArr |= usedSpace
  end

  def script_JumpGosub(cmdDecode, lineHash)
    if @subs[cmdDecode[:opJumpOffset]].nil?
      @subs[cmdDecode[:opJumpOffset]] = [lineHash[:opCodeOffset]]
      @ptrs.push ({"name" => ("sub%03d" % @subCount),
                   "tableptr" => "0x%06X" % cmdDecode[:opJumpOffset],
                   "ptrType" => "s",
                   "structure" => "4,s",
                   "count" => 1,
                   "comment" => "Unk",
                   "isScript" => "true",
                   "lineWidth" => lineHash[:opLineWidth],
                   "parseOnly" => "true"})
      @subCount += 1
      debugPrint "Added sub at " + cmdDecode[:opJumpOffset] + " from " + lineHash[:opCodeOffset]
    else
      @subs[cmdDecode[:opJumpOffset]].push(lineHash[:opCodeOffset])
    end
  end

  def script_Inline(cmdDecode, lineHash)
    inline = cmdDecode[:opInlineCode]
    if inline.include?("lea") && (inline.include?("(pc),a4") || inline.include?("(pc),a0") || inline.include?(".l,a4"))
      lastIndex = 0
      cmdDecode[:opInlineCode].split("\n").each do |l|
        if (l.include?("(pc),a4") || l.include?("(pc),a0") || l.include?(".l,a4")) && !l.include?("3bf06") # Skirmish Strings table
          leaOffset = "0x%06X" % (l.rstrip.split("$")[1].split("(")[0].to_i(16))

          index = nil
          longLea = false

          if l.include?("(pc),a4")
            index = cmdDecode[:opBytes].index('49 FA', lastIndex) + 6
          elsif l.include?("(pc),a0")
            index = cmdDecode[:opBytes].index('41 FA', lastIndex) + 6
          elsif l.include?(".l,a4")
            index = cmdDecode[:opBytes].index('49 F9', lastIndex) + 6
            longLea = true
          else
            raise "Unsupported assembly inline reference in " + cmdDecode[:opBytes].to_s + ":" + lineHash[:opCodeOffset]
          end

          raise "Wrong pointer" if index == nil or index % 3 != 0
          lastIndex = index
          index /= 3

          leaTables = @ptrs.select { |ptr| ptr['specialHandler'] == 'LEA table' }
          isLeaTable = leaTables.any? { |ptr| ptr['tableptr'] == leaOffset }
          leaArr = {:mIndex => index, :mAddr => lineHash[:opCodeOffset], :mLongLea => longLea, :mLeaTable => isLeaTable, :mRefTable => leaOffset}
          if @leas[leaOffset].nil?
            @leas[leaOffset] = [leaArr]
            @ptrs.push ({"name" => ("inl%03d" % @leaCount),
                         "tableptr" => "0x%06X" % leaOffset,
                         "ptrType" => "s",
                         "structure" => "4,s",
                         "count" => 1,
                         "comment" => "Unk",
                         "isScript" => "true",
                         "lineWidth" => lineHash[:opLineWidth],
                         "parseOnly" => "true"})
            @leaCount += 1
          else
            @leas[leaOffset].push leaArr
          end
        end
      end
    end
  end

  # Assign groups to script opcodes
  # A group is a relocable set of opcodes
  def assignGroups()
    @groupID = 0
    @groupOpcodes = {}
    @groupRefLea = {}

    assignGroups_populateHash()

    # Update DB opcode list with assigned groups
    assignGroups_toDB()

    # Exclude those LEA2 pointers that are referencing the same group (to make import memory allocation process more accurate)
    leasSelfReference = @db.execute("SELECT links.mID, src.mGroup, ref.mGroup, links.mOpcode, links.mReference
                 FROM tOpLinks links
                 INNER JOIN tOpcodes src ON links.mOpcode = src.mID
                 INNER JOIN tOpcodes ref ON links.mReference = ref.mID
				         WHERE links.mType = 'LEA2' AND ref.mGroup = src.mGroup")

    leasSelfReference.each do |lea|
      mID = lea[0]
      mSrcGroup = lea[1].to_i
      @db.execute("UPDATE tOpLinks SET mType = 'LEA2SELF' WHERE mID = ?", mID)
      @groupRefLea.delete(mSrcGroup)
    end
  end

  def assignGroups_populateHash
    @opcodePtrs.sort_by { |addr, op| addr }.to_h.each do |addr, op|
      op[:mGroup] = @groupID

      # Find all LEA2s pointing to that opcode
      leas = @db.execute("SELECT mOpcode FROM tOpLinks WHERE mType = 'LEA2' AND mReference = ?", op[:mID])
      if !leas.empty?
        leas.collect! { |x| x[0] }
        @groupRefLea[@groupID] = leas
      end

      opcode = @db.execute("SELECT mName FROM tOpcodes WHERE mID = ?", op[:mID])
      mName = opcode[0][0]
      # The groups differ by 1 if they are adjacent to each other and 2 if not
      if @opcodePtrs[addr + op[:mLength]].nil?
        @groupID += 2
      elsif mName == "op_exit" || mName == "op_jump"
        @groupID += 1
      end
    end
  end

  def assignGroups_toDB
    @opcodePtrs.each do |addr, op|
      @db.execute("UPDATE tOpcodes
        SET mGroup = ?
        WHERE mOpAddr = ?", [op[:mGroup], "0x%06X" % addr])
    end
  end

  def updateDatabaseLinks()
    updateLinks_subs()
    updateLinks_leas()
  end

  def updateLinks_leas
    @leas.each do |dest, srcs|
      srcs.uniq!
      srcs.each do |src|
        ptrType = src[:mLongLea] ? 'LEA4' : (src[:mLeaTable] ? 'LEATABLE' : 'LEA2')
        if ptrType == 'LEATABLE'
          @db.execute("INSERT INTO tOpLinks (mOpcode, mType, mLeaOffset, mRefTable) VALUES (
            (SELECT mID FROM tOpcodes WHERE mOpAddr = ?),
            ?,
            ?,
            ?)", [src[:mAddr], ptrType, src[:mIndex], src[:mRefTable]])
        else
          @db.execute("INSERT INTO tOpLinks (mOpcode, mReference, mType, mLeaOffset) VALUES (
            (SELECT mID FROM tOpcodes WHERE mOpAddr = ?),
            (SELECT mID FROM tOpcodes WHERE mOpAddr = ?),
            ?,
            ?)", [src[:mAddr], dest, ptrType, src[:mIndex]])
        end
      end
    end
  end

  def updateLinks_subs
    @subs.each do |dest, srcs|
      srcs.uniq!
      srcs.each do |src|
        @db.execute("INSERT INTO tOpLinks (mOpcode, mReference, mType) VALUES (
          (SELECT mID FROM tOpcodes WHERE mOpAddr = ?),
          (SELECT mID FROM tOpcodes WHERE mOpAddr = ?),
          'SUB')", [src, dest])
      end
    end
  end

  def compactFreeSpace()
    ranges = @freeSpaceArr.to_ranges
    File.open(Paths::TEMP_PATH + "/freespace.txt", "w+") do |f|
      ranges.each { |element| f.puts("0x%06X" % element.first + " " + "0x%06X" % (element.last - 1)) }
    end
  end

  def exportStaticStrings()
    @ptrs = CSV.read(Paths::PTRS_8X16_CSV, :encoding => "utf-8", :headers => true, :col_sep => ";").map {|p| p.to_h}

    @ptrs.each do |ptr|
      addr = ptr['tableptr'].to_i(16)
      count = ptr['count'].to_i
      strLimit = ptr['strLimit'].to_i
      ptrList = ptr['ptr']
      ptrType = ptr['ptrType']

      curAddr = addr
      count.times do |i|
        str = Util.decStaticString(@romBytes[curAddr, strLimit])
        @staticStrings[curAddr] = {:mLimit => strLimit, :mText => str, :mPtr => ptrList, :mPtrType => ptrType  }
        curAddr += strLimit + 1
      end
    end
  end

  def exportTranslation()
    if Configuration::CreateTranslationTemplate
      @translation.each do |row|
        @t10nDB.execute("INSERT INTO tTranslation (mOpAddr, mASCII, mText) VALUES (?, ?, ?)",[
            row[1],
            row[2],
            row[3]
        ])
      end

      @staticStrings.each do |addr, str|
        @t10nDB.execute("INSERT INTO tStaticStrings (mAddr, mText, mStrLimit, mPtrAddr, mPtrType) VALUES (?, ?, ?, ?, ?)",[
            "0x%06X" % addr,
            str[:mText],
            str[:mLimit],
            str[:mPtr],
            str[:mPtrType],
        ])
      end
    end
  end
end

class DataImporter
  def initialize(_db, _langDB, _patchedRom)
    @db = _db
    @patchedImage = _patchedRom
    @groupsHash = {}
    @newOpAddrs = {}
    @inlineRef = {}
    @extraData = {}

    # Get translation strings from translation DB
    importTranslation(_langDB)

    # Get vacant ROM space information
    readFreeSizeInfo(Paths::FREESPACE_CSV)
  end

  def readFreeSizeInfo(_infoFile)
    freeSizeCSV = CSV.read(_infoFile, :encoding => "utf-8", :headers => true, :col_sep => ";")
    @freeSizeArr = Array.new
    freeSizeCSV.each do |f|
      @freeSizeArr.push [f["startAddr"].to_i(16), f["endAddr"].to_i(16), f["priority"].to_i]
    end
    @freeSpaceIdx = 0
  end

  def importTranslation(_langDB)
    @translation = {}
    t10nDB = SQLite3::Database.open(_langDB)
    transTable = t10nDB.execute("SELECT mOpAddr, mTranslation FROM tTranslation")
    transTable.each do |t|
      mOpAddr = t[0]
      mTranslation = t[1]

      @translation[mOpAddr] = mTranslation
    end

    @staticStrings = {}
    staticTable = t10nDB.execute("SELECT mID, mAddr, mText, mStrLimit, mTranslation, mPtrAddr, mPtrType FROM tStaticStrings")
    staticTable.each do |str|
      @staticStrings[str[0]] = {:mAddr => str[1], :mText => str[2], :mStrLimit => str[3], :mTranslation => str[4].to_s, :mPtrAddr => str[5], :mPtrType => str[6]}
    end
  end

  def eraseEmptyBlocks
    @freeSizeArr.each do |block|
      length = block[1] - block[0] + 1
      length.times { |i| @patchedImage[block[0] + i] = 0 }
    end
  end

  # Replace original string with translated ones
  # Then calculate length of each group and build hash containing all of them
  def buildTranslatedScripts()
    groups = @db.execute("SELECT mGroup, COUNT(mID) FROM tOpcodes GROUP BY mGroup")
    groups.each do |s|
      mGroup = s[0]
      groupCount = s[1]

      # Check if group has 68000 position dependent opcodes
      callsInl = @db.execute("SELECT mID, mName FROM tOpcodes WHERE mGroup = " + mGroup.to_s + " AND (mName = 'op_callfunction' OR mName = 'op_inlinecode')")
      hasCalls = callsInl.length > 0

      opcodes = @db.execute("SELECT mID, mLength, mByte, mParams, mName, mOpAddr, mIsScript, mLineWidth FROM tOpcodes WHERE mGroup = " + mGroup.to_s + " ORDER BY mOpAddr")
      scriptHash = {}
      scriptLength = 0

      opcodes.each do |o|
        mID = o[0]
        mLength = o[1]
        mByte = o[2]
        mParams = o[3]
        mName = o[4]
        mOpAddr = o[5]
        mIsScript = eval(o[6])
        mLineWidth = o[7]

        if mName == "op_text" && !@translation[mOpAddr].nil? && @translation[mOpAddr] != ""
          # translate string
          translated = String.new(@translation[mOpAddr])
          # process string (add line breaks etc.)
          trMessage = Util.prepareString(translated,mLineWidth, mIsScript)
          # convert string to bytes
          trBytes = Util.encodeString(trMessage)
          scriptLength += trBytes.length
          # insert it
          scriptHash[mID] = {:opAddr => nil, :opData => trBytes}
        elsif mName == "op_callfunction" || mName == "op_inlinecode"
          # consider 68000 even address restriction for words and dwords
          data = []
          data.push mByte.to_i(16)
          data.push 0 if (data.length + scriptLength).modulo(2) != 0
          params = mParams.split(" ").map{|b| b.to_i(16)}
          data += Util.numToBytes(params.length + 2,2,false)
          paramsOff = data.length
          data += params
          scriptLength += data.length
          scriptHash[mID] = {:opAddr => nil, :opData => data, :opOffset => paramsOff }
        else
          scriptLength += mLength
          data = mParams.split(" ").map{|b| b.to_i(16)}
          if mName != "op_text"
            data.unshift(mByte.to_i(16))
          else
            debugPrint "WARNING: Not translated at " + "0x%06X" % mOpAddr
          end
          raise "Wrong length for op " + mID.to_s if mLength != data.length
          scriptHash[mID] = {:opAddr => nil, :opData => data}
        end
      end
      @groupsHash[mGroup] = {:mLength => scriptLength, :mBytes => scriptHash, :hasCalls => hasCalls, :isAllocated => false }
    end
  end

  def buildMergeExtraBlocks
    extra = @db.execute("SELECT mID, mOpCode, mPos, mBytes, mPtrs FROM tOpExtra")
    extra.each do |ex|
      mID = ex[0]
      mOpCode = ex[1]
      mPos = ex[2]
      mBytes = eval(ex[3])
      mPtrs = eval(ex[4])

      data = mBytes
      pasteOff = scriptMalloc(data.length, true)
      data.length.times do |i|
        @patchedImage[pasteOff + i] = data[i]
      end

      scripts = []
      mPtrs.each do |ptr|
        extra = @db.execute("SELECT mID FROM tOpcodes WHERE mOpAddr = ?", ptr)
        raise ("No opcode found for extra reference " + ptr) unless extra.length == 1
        scripts.push extra[0][0]

        @extraData[mOpCode] = {:mAddr => pasteOff, :mScriptRefs => scripts}
      end
    end
  end

  # A nightmare of a memory management
  def scriptMalloc(_requiredBytes, _evenAddr = false, _minAddr = Const::ROM_MinAddr, _maxAddr = Const::ROM_MaxAddr)
    # Sort all memory blocks by priority
    @freeSizeArr.sort_by! {|op| op[2]}
    @freeSpaceIdx = 0
    toDivide = []
    loop do
      block = @freeSizeArr[@freeSpaceIdx]
      raise "Memory corruption " if block[0] > block[1]

      availSpace = block[1] - block[0] + 1
      required = _requiredBytes
      if required <= availSpace
        # Check block left offset
        pasteOff = block[0]
        evenByte = (_evenAddr && pasteOff.modulo(2) != 0) ? 1 : 0
        if required < availSpace || evenByte == 0
          pasteOff += evenByte
          if pasteOff >= _minAddr && pasteOff + required <= _maxAddr
            block[0] += required + evenByte
            if block[0] > block[1]
              @freeSizeArr.delete_at(@freeSpaceIdx)
            end
            return pasteOff
          end
        end
        # Check block right offset
        pasteOff = block[1]  - required + 1
        evenByte = (_evenAddr && pasteOff.modulo(2) != 0) ? 1 : 0
        if required < availSpace || evenByte == 0
          pasteOff -= evenByte
          if pasteOff >= _minAddr && pasteOff + required <= _maxAddr
            block[1] = pasteOff - evenByte - 1
            if block[0] > block[1]
              @freeSizeArr.delete_at(@freeSpaceIdx)
            end
            return pasteOff
          end
          # If both options fail, try to divide a block later
          if block[0] <= _minAddr && block[1] >= _maxAddr
            toDivide.push @freeSpaceIdx
          end
        end
      end
      @freeSpaceIdx += 1
      if (@freeSpaceIdx >= @freeSizeArr.length)
        # If block is big enough, allocate space inside block and divide it
        if toDivide.length > 0
          block = @freeSizeArr[toDivide[0]]
          pasteOff = _minAddr
          evenByte = ((_evenAddr && pasteOff.modulo(2) != 0) ? 1 : 0)
          pasteOff += evenByte

          newBlock = [pasteOff + required, block[1], 99]
          block[1] = pasteOff - 1
          @freeSizeArr.push newBlock

          return pasteOff
        end

        # Unable to allocate memory with given restrictions
        printScriptMem()
        raise "No more free script space! Required " + required.to_s + " bytes between " + "0x%06X" % _minAddr + "-" + "0x%06X" % _maxAddr
      end
    end
  end

  def printScriptMem
    @freeSizeArr.each do |x|
      debugPrint "0x%06X" % x[0] + "-" + "0x%06X" % x[1] + ":" + (x[1] - x[0] + 1).to_s
    end
  end

  def mergeScripts
    @groupsHash.each do |gId, group|
      # Skip already allocated groups
      if group[:isAllocated]
        next
      end

      # Prepare 2 arrays with address allocation restrictions for 2-byte pointers
      minAllow = [Const::ROM_MinAddr]
      maxAllow = [Const::ROM_MaxAddr]

      merge_AllocateAndMerge(gId, group, minAllow, maxAllow)
    end

    # Print how much memory is left
    printScriptMem
  end

  # Add pointers from tPointers into address allocation restrictions arrays
  def merge_ConsiderStaticPointers(gId, minAllow, maxAllow)
    # Get minimum and maximun address within a group
    minmaxAddrs = @db.execute("SELECT MIN(mOpAddr), MAX(mOpAddr)
                              FROM tOpcodes
                              WHERE mGroup = ?", gId)


    min = minmaxAddrs[0][0]
    max = minmaxAddrs[0][1]

    # Iterate over all pointers
    pointers = @db.execute("SELECT mID, mTable, tPointers.mPtr, mPtrRef, mReference, mIndex, mMinAddr, mMaxAddr, tData.mPtr, tData.mPtrType, tData.mStructure, tData.mTablePtr
                              FROM tPointers
                              INNER JOIN tData ON tPointers.mTable = tData.mTableID
                              WHERE mPtrRef >= ? AND mPtrRef <= ?", [min, max])

    pointers.each do |p|
      mID = p[0]
      mTable = p[1]
      mPtr = p[2]
      mPtrRef = p[3]
      mReference = p[4]
      mIndex = p[5]
      mMinAddr = p[6]
      mMaxAddr = p[7]
      mTablePtr = p[8]
      mTableType = p[9]
      mStructure = p[10]
      mTableRef = p[11]

      # Check if this pointer has manual address restriction in CSV file
      if !mMinAddr.nil? && !mMaxAddr.nil?
        minAllow.push mMinAddr.to_i(16)
        maxAllow.push mMaxAddr.to_i(16)
      else
        # Check if it's 2 byte relative and and restriction depending on its type
        isRelativePtr = mStructure.include?('s') && mTableType.include?('r')
        isRelative = isRelativePtr || (!mStructure.include?('d') && !mStructure.include?('s'))
        if isRelative
          if isRelativePtr
            minAllow.push mTableRef.to_i(16) - 0x8000
            maxAllow.push mTableRef.to_i(16) + 0x7FFF
          elsif mStructure.include?('f')
            minAllow.push mPtr.to_i(16) - 0x8000
            maxAllow.push mPtr.to_i(16) + 0x7FFF
          elsif mStructure.include?('r')
            minAllow.push mTablePtr.to_i(16) - 0x8000
            maxAllow.push mTablePtr.to_i(16) + 0x7FFF
          elsif mStructure.include?('n')
            minAllow.push mTablePtr.to_i(16)
            maxAllow.push mTablePtr.to_i(16) + 0x7FFF
          else
            raise "Wrong relative pointer at " + mPtr
          end
        end
      end
    end
  end

  # Check if this script group references a pointer table with inline LEA2 pointer
  def merge_ConsiderInlineTables(gId, minAllow, maxAllow)
    inlineTables = @db.execute("SELECT tOpcodes.mGroup, mOpcode, mType, mRefTable
                              FROM tOpcodes
                              INNER JOIN tOpLinks ON tOpcodes.mID = tOpLinks.mOpcode
							                WHERE tOpcodes.mGroup = ? AND tOpLinks.mType = 'LEATABLE'", [gId])

    inlineTables.each do |t|
      mRefTable = t[3].to_i(16)
      minAllow.push mRefTable - 0x8000
      maxAllow.push mRefTable + 0x7FFF
    end
  end

  # Allocate ROM space for script group and merge it to ROM
  def merge_AllocateAndMerge(gId, group, minAllow, maxAllow)
    merge_ConsiderStaticPointers(gId, minAllow, maxAllow)
    merge_ConsiderInlineTables(gId, minAllow, maxAllow)
    # Mark this as allocated (so it's safe to allocate all inline LEA2 dependent script groups)
    group[:isAllocated] = true

    # Check if this opcode group is referenced by other groups and allocate them now
    leasRefs = @db.execute("SELECT links.mID, links.mType, links.mLeaOffset, src.mGroup, ref.mGroup, links.mOpcode, links.mReference
                              FROM tOpLinks links
                              INNER JOIN tOpcodes src ON links.mOpcode = src.mID
                              INNER JOIN tOpcodes ref ON links.mReference = ref.mID
                              WHERE links.mType = 'LEA2' AND ref.mGroup = ?", [gId])
    leasRefs.each do |l|
      mSrcGroup = l[3]
      if !@groupsHash[mSrcGroup][:isAllocated]
        debugPrint "Allocating LEA2 group %d" % mSrcGroup
        off = merge_AllocateAndMerge(mSrcGroup, @groupsHash[mSrcGroup], minAllow, maxAllow)
        # Little margin for LEA2 inline refs
        minAllow.push(off - 0x6000)
        maxAllow.push(off + 0x5FFF)
      end
    end

    minAddr = minAllow.max
    maxAddr = maxAllow.min
    debugPrint "Processing script group " + gId.to_s #+ ", static pointers - " +  pointers.length.to_s + ", inline LEAs - " + inlines.length.to_s
    debugPrint "Valid space in ROM between " + "0x%06X" % minAddr + "-" +  "0x%06X" % maxAddr
    raise "Can't allocate this script group, pointers are out of range." if minAddr > maxAddr

    pasteOff = scriptMalloc(group[:mLength], group[:hasCalls], minAddr, maxAddr)
    debugPrint "Allocated block from " + "0x%06X" % pasteOff + " to " "0x%06X" % (pasteOff + group[:mLength])

    # Now copy all script data to its real location in patched ROM
    group[:mAddr] = pasteOff
    mergedBytes = []
    opAddr = pasteOff

    #  First build an array with patch bytes
    group[:mBytes].each do |opid, op|
      op[:opAddr] = opAddr
      raise "Opcode %d has been already assigned with address: %x" % [opid, @newOpAddrs[opid]] if !@newOpAddrs[opid].nil?
      @newOpAddrs[opid] = opAddr
      if op[:opData][0] == 0x09 # stupid inline 2 byte LEAs
        raise "No offset" if op[:opOffset].nil?

        # Set self-referencing LEA2s first
        leasSelf = @db.execute("SELECT mLeaOffset, mReference
                              FROM tOpLinks
                              WHERE mType = 'LEA2SELF' AND mOpcode = ?", [opid])
        leasSelf.each do |l|
          mLeaOffset = l[0].to_i
          mReference = l[1]
          leaAddr = op[:opAddr] + op[:opOffset] + mLeaOffset

          @inlineRef[leaAddr] = mReference
        end

        # Check which script groups this opcode references
        leasOps = @db.execute("SELECT links.mID, links.mType, links.mLeaOffset, src.mGroup, ref.mGroup, links.mOpcode, links.mReference
                              FROM tOpLinks links
                              INNER JOIN tOpcodes src ON links.mOpcode = src.mID
                              INNER JOIN tOpcodes ref ON links.mReference = ref.mID
                              WHERE links.mType = 'LEA2' AND src.mGroup = ? AND links.mOpcode = ?", [gId, opid])

        leasOps.each do |l|
          mSrcGroup = l[3]
          mRefGroup = l[4]
          mReference = l[6]
          mLeaOffset = l[2].to_i

          leaAddrRef = op[:opAddr] + op[:opOffset] + mLeaOffset
          @inlineRef[leaAddrRef] = mReference

          if !@groupsHash[mRefGroup][:isAllocated]
            leaMin = [leaAddrRef - 0x8000]
            leaMax = [leaAddrRef + 0x7FFF]
            debugPrint "Allocating reference to LEA2 group %d" % mRefGroup
            merge_AllocateAndMerge(mRefGroup, @groupsHash[mRefGroup], leaMin, leaMax)
          end
        end
      end
      opAddr += op[:opData].length
      mergedBytes += op[:opData]
    end
    # Check if we have allocated all requested space
    raise "Script length mismatch! %d != %d" % [mergedBytes.length, group[:mLength]] if mergedBytes.length != group[:mLength]
    # Now merge the patch
    mergedBytes.length.times do |i|
      raise "Wrong type " + mergedBytes[i].class.name if mergedBytes[i].class != Integer
      @patchedImage[pasteOff + i] = mergedBytes[i]
    end

    # Return address in patched ROM
    return group[:mAddr]
  end

  def printAvailableSpace(printRequired = false)
    size = 0
    @freeSizeArr.each do |x|
      size += x[1] - x[0]
    end
    debugPrint "Free space available: " + size.to_s + " bytes"
    if printRequired
      size = 0
      @groupsHash.each do |k, v|
        size += v[:mLength]
      end

      debugPrint "Required space: " + size.to_s + " bytes"
    end
  end

  # Fix pointers for 0x007184 extra blocks
  def fixExtraBlocks
    @extraData.each do |op, ex|
      srcAddr = @newOpAddrs[op]
      dstAddr = Util.numToBytes(ex[:mAddr], 4, false)
      evenByte = srcAddr.modulo(2) != 0 ? 0 : 1
      dstAddr.length.times do |i|
        @patchedImage[srcAddr + evenByte + 7 + i] = dstAddr[i]
      end

      srcOffset = ex[:mAddr] + 2
      ex[:mScriptRefs].each do |s|
        srcOffset += 2
        dstAddr = Util.numToBytes(@newOpAddrs[s], 4, false)
        dstAddr.length.times do |i|
          @patchedImage[srcOffset + i] = dstAddr[i]
        end
        srcOffset += 4
        if (ex[:mScriptRefs].count > 0)
          srcOffset += 2
        end
      end
    end
  end

  # Fix all inline LEA pointers
  def fixLeaPointers
    # the easiest ones - 4 byte LEAs
    leas = @db.execute("SELECT mOpcode, mReference, mLeaOffset FROM tOpLinks WHERE mType = 'LEA4'")
    leas.each do |l|
      mOpcode = l[0]
      mReference = l[1]
      mExtra = l[2]

      srcAddr = @newOpAddrs[mOpcode.to_i]
      evenAddr = ((srcAddr + 1).modulo(2) != 0) ? 1 : 0
      srcAddr += evenAddr + 3
      dstAddr = Util.numToBytes(@newOpAddrs[mReference.to_i], 4, false)

      dstAddr.length.times do |i|
        @patchedImage[srcAddr + mExtra.to_i + i] = dstAddr[i]
      end
    end

    # LEA2s to tables
    leasTables = @db.execute("SELECT mOpcode, mLeaOffset, mRefTable FROM tOpLinks WHERE mType = 'LEATABLE'")
    leasTables.each do |l|
      mOpcode = l[0]
      mLeaOffset = l[1]
      mRefTable = l[2]

      srcAddr = @newOpAddrs[mOpcode.to_i]
      evenAddr = ((srcAddr + 1).modulo(2) != 0) ? 1 : 0
      srcAddr += evenAddr + 3
      dst, ptrSize = Util.calculatePtr(mRefTable.to_i(16), srcAddr + mLeaOffset.to_i, 'r')
      dstAddr = Util.numToBytes(dst, 2, false)

      dstAddr.length.times do |i|
        @patchedImage[srcAddr + mLeaOffset.to_i + i] = dstAddr[i]
      end
    end

    # LEA2s to other opcodes
    @inlineRef.each do |addr, ref|
      srcAddr = addr
      dst, ptrSize = Util.calculatePtr(@newOpAddrs[ref], addr, 'r')
      dstAddr = Util.numToBytes(dst, ptrSize, false)
      dstAddr.length.times do |i|
        @patchedImage[srcAddr + i] = dstAddr[i]
      end
    end
  end

  # Fix op_jump and op_gosub opcode pointers
  def fixSubPointers
    subs = @db.execute("SELECT mOpcode, mReference FROM tOpLinks WHERE mType = 'SUB'")
    subs.each do |l|
      mOpcode = l[0]
      mReference = l[1]

      srcAddr = @newOpAddrs[mOpcode.to_i]
      dstAddr = Util.numToBytes(@newOpAddrs[mReference.to_i], 4, false)

      dstAddr.length.times do |i|
        @patchedImage[srcAddr + 1 + i] = dstAddr[i]
      end
    end
  end

  # Fix tPointers table pointers
  def fixStaticPointers
    ptrs = @db.execute("SELECT tPointers.mID, tPointers.mPtr, tPointers.mReference, tPointers.mMSB, tData.mPtr, tData.mPtrType, tData.mStructure, tData.mTablePtr, tPointers.mTable
                        FROM tPointers
                        INNER JOIN tData ON tPointers.mTable = tData.mTableID")
    ptrs.each do |ptr|
      mID = ptr[0]
      mPtr = ptr[1]
      mReference = ptr[2]
      mMSB = eval(ptr[3])
      mTablePtr = ptr[4]
      mTablePtrType = ptr[5]
      mStructure = ptr[6]
      mTableRef = ptr[7]
      mTableName = ptr[8]

      if (mReference == -1) # no pointer
        next
      end

      raise "No address for reference " + mReference.to_s if @newOpAddrs[mReference.to_i].nil?
      dstAddr = @newOpAddrs[mReference.to_i]

      if mStructure.include?('s')
        srcPtrs = mTableRef.split(",")
        ptrType = mTablePtrType
      else
        srcPtrs = mPtr.split(",")
        ptrType = mStructure.scan(/([a-z])/)
        raise "Wrong pointer type" if ptrType.length != 1
        ptrType = ptrType[0][0]
      end

      srcPtrs.each do |src|
        src = src.to_i(16)
        isRelativePtr = mStructure.include?('s') && mTablePtrType.include?('r')
        if isRelativePtr
          ptrAddr, ptrSize = Util.calculatePtr(dstAddr, mTableRef.to_i(16), ptrType, mMSB)
        elsif mStructure.include?('f')
          ptrAddr, ptrSize = Util.calculatePtr(dstAddr, src, ptrType, mMSB)
        else
          ptrAddr, ptrSize = Util.calculatePtr(dstAddr, mTablePtr.to_i(16), ptrType, mMSB)
        end

        patchAddr = Util.numToBytes(ptrAddr, ptrSize, false)
        patchAddr.length.times do |i|
          @patchedImage[src + i] = patchAddr[i]
        end
      end
    end
  end

  def mergeStaticStrings
    staticPtrs = CSV.read(Paths::PTRS_8X16_CSV, :encoding => "utf-8", :headers => true, :col_sep => ";").map {|p| p.to_h}
    relOffset = Const::Strings_RelStart
    dirOffset = Const::Strings_DirStart
    staticPtrs.each do |ptr|
      ptrCount = ptr["count"].to_i
      strs = @staticStrings.select {|id, str| ptr["ptr"] == str[:mPtrAddr]}
      raise "Incorrect number of strings for ptr %x!" % ptr["ptr"] if ptrCount != strs.length
      if ptr["ptrType"] == 'd'
        currentOffset = newDst = dirOffset
      else
        currentOffset = newDst = relOffset
      end

      strs.each { |id, str|
        charCount = 0
        charMax = ptr["strLimit"].to_i * 2
        while charCount < charMax do
          if str[:mTranslation][charCount].nil?
            char = 0x20
          else
            char = str[:mTranslation][charCount].ord
          end
          @patchedImage[currentOffset] = char
          currentOffset += 1
          charCount += 1
        end
        while charCount <= 16 do
          @patchedImage[currentOffset] = 0xff
          currentOffset += 1
          charCount += 1
        end
      }
      if currentOffset.modulo(2) == 1
        currentOffset += 1
      end
      ptr["ptr"].split(',').each { |p|
        if ptr["ptrType"] == 'r'
          src = 0x27000 # value in register A5
        else
          src = p.to_i(16)
        end

        newPtr, ptrSize = Util.calculatePtr(newDst, src, ptr["ptrType"])
        patchAddr = Util.numToBytes(newPtr, ptrSize, false)
        src = p.to_i(16)
        patchAddr.length.times do |i|
          @patchedImage[src + i] = patchAddr[i]
        end
      }
      if ptr["ptrType"] == 'd'
        dirOffset = currentOffset
      else
        relOffset = currentOffset
      end
    end
  end

  def importData()
    # Scripts port
    eraseEmptyBlocks()
    buildTranslatedScripts()
    printAvailableSpace(true)
    mergeScripts()
    buildMergeExtraBlocks()
    fixStaticPointers()
    fixSubPointers()
    fixLeaPointers()
    fixExtraBlocks()
    printAvailableSpace()

    # Static strings
    mergeStaticStrings()
  end
end

class ResEncoder
  def initialize(_romBytes)
    @romBytes = _romBytes
    @resAddr = []
  end

  def getByte
    byte = @romBytes[@picOffset]
    @picOffset += 1
    return byte
  end

  def getBit
    bit = @bitArray.shift
    if bit.nil?
      @bitArray += ("%08b" % getByte).reverse.chars
      return @bitArray.shift
    else
      return bit
    end
  end

  def decode(_offset)
    @bitArray = Array.new
    @picOffset = _offset
    encodeType = getByte
    decodeSize = (getByte << 8) + getByte

    decodedBytes = Array.new

    if encodeType == 0x83 || encodeType == 0x3
      while decodedBytes.size <= decodeSize
        if getBit == "1"
          decodedBytes.push getByte
        else
          seekBack = getByte
          seekAndCounter = getByte
          seekBack += (seekAndCounter & 0xf0) << 4
          counter = (seekAndCounter & 0x0f) + 2
          copystart = decodedBytes.size - seekBack
          0.upto(counter) do |t|
            decodedBytes.push decodedBytes[copystart+t]
          end
        end
      end
    elsif encodeType == 0x84 || encodeType == 0x4
      while decodedBytes.size <= decodeSize
        if getBit == "1"
          decodedBytes.push getByte
        else
          if getBit == "1"
            seekBack = getByte
            seekAndCounter = getByte
            seekBack += (seekAndCounter & 0xf8) << 5
            counter = seekAndCounter & 0x07
            if counter == 0
              counter = getByte
            else
              counter += 1
            end
          else
            bitStr = getBit
            bitStr += getBit
            counter = bitStr.to_i(2) + 2
            seekBack = getByte
          end
          copystart = decodedBytes.size - seekBack
          0.upto(counter) do |t|
            decodedBytes.push decodedBytes[copystart+t]
          end
        end
      end
    else
      return nil
    end
    return decodedBytes[0, decodeSize]
  end

  def lzsa2encode(_addr, _bytes, _mEncodeType, _custom)
    inName = RES_EXTRACT_PATH + "/d_0x%06X.bin" % _addr
    outName = RES_EXTRACT_PATH + "/e_0x%06X.bin" % _addr
    if _custom || (!File.file?(inName) && !_bytes.nil?)
      debugPrint inName
      IO.binwrite(inName, _bytes.pack('c*'))
    end

    if (Configuration::RepackResourses || _custom || !File.file?(outName))
      stdin, stdout, stderr, wait_thr = Open3.popen3(Paths::LZSA_EXE + ' -f 2 --prefer-speed "' + inName + '" ""' + outName + '"')
      pid = wait_thr[:pid]
      stdout.read
    end

    encodedFile = IO.binread(outName).bytes
    blockSize = Util.bytesToNum(encodedFile[3, 2], true)
    encodedFile = Util.numToBytes(blockSize, 2, false) + encodedFile[6, blockSize] # Util.numToBytes(encodedFile.length, 2, false)
    encodedFile.unshift(_mEncodeType)
    return encodedFile
  end

  def repackData()
    origResSize = newResSize = 0
    @gfxReplaceTable = CSV.read(Paths::GFX_REPLACE_CSV, :encoding => "utf-8", :headers => true, :col_sep => ";").map {|p| p.to_h}
    Const::Resources_Count.times do |i|
      @resAddr.push({ :mIndex => i, :mAddr => Util.bytesToNum(@romBytes[Const::Resources_Offset + i*3, 3], false)} )
    end
    @resAddr.sort_by! {|r| r[:mAddr]}
    @resAddr.each_cons(2) do |x, y|
      x[:mOrigSize] = y[:mAddr] - x[:mAddr]
      x[:mBytes] = @romBytes[x[:mAddr], x[:mOrigSize]]
    end
    @resAddr.last[:mOrigSize] = 0x41C # calculated
    @resAddr.last[:mBytes] = @romBytes[@resAddr.last[:mAddr], @resAddr.last[:mOrigSize]]

    currentOffset = Const::Resources_End
    @resAddr.reverse_each do |res|
      toCompress = true # should the resource be recompressed
      origResSize += res[:mOrigSize]
      toReplace = @gfxReplaceTable.select { |item| item["idx"].to_i == res[:mIndex] }
      if toReplace.empty?
        decoded = decode(res[:mAddr])
        if decoded.nil?
          toCompress = false
        else
          res[:mBytes] = decoded.compact
        end
        custom = false
      else
        res[:mBytes] = IO.binread(Paths::GFX_PATH + '/' + toReplace[0]['replaceGfx']).bytes
        debugPrint "Replaced " + toReplace[0]['replaceGfx']
        custom = true
      end
      res[:mEncodeType] = @romBytes[res[:mAddr]]

      if !res[:mBytes].nil? && toCompress
        res[:mBytes] = lzsa2encode(res[:mAddr], res[:mBytes], res[:mEncodeType], custom)
      end
      resLength = res[:mBytes].length
      newResSize += resLength
      currentOffset -= resLength
      resLength.times do |i|
        @romBytes[currentOffset + i] = res[:mBytes][i]
      end
      newAddr = Util.numToBytes(currentOffset, 3, false)
      newAddr.length.times do |i|
        @romBytes[Const::Resources_Offset + res[:mIndex]*3 + i] = newAddr[i]
      end
    end

    debugPrint "Resorce area starts at 0x%x" % currentOffset
    debugPrint "LZSA2 re-compression saved %d bytes" % [origResSize - newResSize]
  end
end

# Applies all ASM patches and creates hooks in code
def patchASM(_rom)
  symbolsArray = {}
  asmFiles = CSV.read(Paths::ASM_CSV, :encoding => "utf-8", :headers => true, :col_sep => ";").map {|p| p.to_h}
  asmFiles.each do |asm|
    asmSource = Paths::ASM_PATH + '/' + asm['asmFile'] + '.asm'
    asmBinary = Paths::TEMP_PATH + '/' + asm['asmFile'] + '.bin'
    asmList = Paths::TEMP_PATH + '/' + asm['asmFile'] + '.lst'
    stdin, stdout, stderr, wait_thr = Open3.popen3(Paths::VASM + ' -L ' + asmList + ' -m68000 -Fbin -o "' + asmBinary + '" ""' + asmSource + '"')
    pid = wait_thr[:pid]
    errors = stderr.read

    raise "ASM compilation error for " + asmSource + ": " + errors if !errors.empty?
    asmBin = IO.binread(asmBinary).bytes
    raise "Compiled file size exceeds available block size - " + asmBinary + ": %d != %d" % [asmBin.length, asm["blockSize"]] if asmBin.length > asm["blockSize"].to_i
    debugPrint "ASM bundle used %d/%d bytes" % [asmBin.length, asm["blockSize"].to_i]
    dstOffset = asm["dstAddr"].to_i(16)
    asmBin.size.times { |i| _rom[i + dstOffset] = asmBin[i] }
    symbols = File.readlines(asmList, :encoding => "ISO-8859-1").map do |line|
      line.split(' ')
    end
    # Get symbol offset by analyzing vasm listing file
    symbols.delete_if { |line| line.empty? || !line[0].include?('sym_')}
    symbols.map! { |line|  {:mSymbol => line[0], :mOffset => line[2][(/0x\w+/)].to_i(16)}}
    symbols.each { |sym|
      symbolsArray[sym[:mSymbol]] = {:mAddr => dstOffset, :mOffset =>sym[:mOffset] }
    }
  end

  asmLinks = CSV.read(Paths::ASM_LINKS_CSV, :encoding => "utf-8", :headers => true, :col_sep => ";").map {|p| p.to_h}
  asmLinks.each do |asm|
    symbol = asm['symbol']
    srcOffset = asm['srcAddr']
    symAddr = symbolsArray.select { |sym, addrs| symbol == sym }
    raise "Symbol not found: %s" % symbol if symAddr.empty?
    symAddr = symAddr.first

    if !srcOffset.nil?
      srcOffset = srcOffset.split(",")
    end
    dstOffset = symAddr[1][:mAddr] + symAddr[1][:mOffset]
    if !asm["linkType"].nil?
      linkCode = Array.new
      if asm["linkType"] == "r"
        linkCode += [0x4e, 0xb9] # JSR <>.L
      elsif asm["linkType"] == "d"
        linkCode += [0x4e, 0xf9] # JMP <>.L
      end
      linkCode.push (dstOffset & 0xff000000) >> 24
      linkCode.push (dstOffset & 0x00ff0000) >> 16
      linkCode.push (dstOffset & 0x0000ff00) >> 8
      linkCode.push (dstOffset & 0x000000ff)
      if !asm["addBytes"].nil?
        addBytes = asm["addBytes"].to_i
        addBytes.times { linkCode += [0x4e, 0x71] } # NOP
      else
        linkCode += [0x4e, 0x75] # RTS
      end
      srcOffset.each do |src|
        srcoff = src.to_i(16)
        linkCode.size.times { |i| _rom[i + srcoff] = linkCode[i] }
      end
    end
  end
end

def generateVWF(_rom)
  tileBytes = Array.new

  img = ChunkyPNG::Image.from_file(Paths::DATA_FONT_TRIO)
  charWidth = 8
  charHeight = 16

  tileBytes = Array.new
  tileWidths = Array.new
  6.times do |y|
    16.times do |x|
      part = img.crop(x * charWidth, (y + 2) * charHeight, charWidth, charHeight)
      leftX = 0
      rightX = charWidth - 1
      letterWidth = 4
      if x > 0 || y > 0
        4.times do |r|
          leftColumn = Array.new
          rightColumn = Array.new
          16.times do |y|
            leftColumn.push part.get_pixel(leftX, y)
            rightColumn.push part.get_pixel(rightX, y)
          end
          leftX += 1 if leftColumn.uniq.size == 1
          rightX -= 1 if rightColumn.uniq.size == 1
        end
        letterWidth = rightX - leftX + 1
        picWidth = letterWidth
        picWidth = 4 if picWidth < 4
        part.crop!(leftX, 0, picWidth, charHeight)
        letterWidth += 1
      end
      charHeight.times do |line|
        bs = String.new
        charWidth.times do |pixel|
          if pixel < part.width
            if part[pixel, line] > 0xff
              bs += "1"
            else
              bs += "0"
            end
          else
            bs += "0"
          end
        end
        #puts bs.to_i(2)
        tileBytes.push bs.to_i(2)
        tileBytes.push 0
      end
      tileWidths.push letterWidth
        #part.save(("./letter_"+y.to_s+"x"+x.to_s+".png"), :interlace => true)
    end
  end
  tileWidths.push 0x08
#IO.binwrite("tilebytes.bin", tileBytes.pack('c*'))
  tileWidths.size.times { |i| _rom[i + 0x19adc0] = tileWidths[i] }
  tileBytes.size.times { |i| _rom[i + 0x19aec0] = tileBytes[i] }
end

def patchFont(_rom)
  generateVWF(_rom)
end

def applyBinaryPatches(_rom)
  binPatches = CSV.read(Paths::PATCHBIN_CSV, :encoding => "utf-8", :headers => true, :col_sep => ";").map {|p| p.to_h}
  binPatches.each do |bin|
    patchFile = IO.binread(Paths::GFX_PATH + '/' + bin['file']).bytes
    addr = bin['addr'].to_i(16)
    patchFile.length.times do |i|
      _rom[addr + i] = patchFile[i]
    end
  end
end

def fixTutorialTimings(_rom)
  # Buttons
  # 01 - up
  # 02 - down
  # 04 - left
  # 08 - right
  # 10 - B
  # 20 - C
  # 40 - A
  # 80 - Start
  tutorial_file = CSV.read(Paths::TUTORIAL_CSV,   :encoding => "utf-8", :headers => true, :col_sep => ";").map {|p| p.to_h}
  flowPtr = Const::Data_TutFlowStart
  timingPtr = Const::Data_TutTimingsStart
  tutorial_file.each do |t|
    if !t['flow'].nil?
      num = Util.numToBytes(t['flow'].to_i(16),2,false)
      _rom[flowPtr] = num[0]
      _rom[flowPtr + 1] = num[1]
      flowPtr += 2
    end
    if !t['button'].nil?
      _rom[timingPtr] = t['button'].to_i(16)
      _rom[timingPtr + 1] = t['delay'].to_i(16)
      timingPtr += 2
    end
  end
end

def hacks_TitleLabels(_rom)
  # shift sprite array position
  _rom[0x01e584] = 0x00
  _rom[0x01e585] = 0xae
  # Tokoton sentou densetsu sprite data position
  _rom[0x01e652] = 0x00
  _rom[0x01e653] = 0x1f
  _rom[0x01e654] = 0xff
  _rom[0x01e655] = 0xa0
  # ... and screen position before fly-by
  _rom[0x01e656] = 0x00
  _rom[0x01e657] = 0x00
  _rom[0x01e658] = 0x00
  _rom[0x01e659] = 0xff

  # new tile map index
  _rom[0x01e650] = 0xc3
  _rom[0x01e651] = 0xaa
  # actual sprite data
  bytes = [0x00,0x07,
           0x00,0x30,0x0d,0x00,
           0x00,0x00,0xff,0x84,
           0x00,0x00,0x0D,0x00,
           0x00,0x08,0x00,0x20,
           0x00,0x00,0x0D,0x00,
           0x00,0x10,0x00,0x20,
           0x00,0x00,0x0D,0x00,
           0x00,0x18,0x00,0x20,
           0x00,0x00,0x0D,0x00,
           0x00,0x20,0x00,0x20,
           0x00,0x00,0x0D,0x00,
           0x00,0x28,0x00,0x20,
           0x00,0x00,0x0D,0x00,
           0x00,0x30,0x00,0x20,
           0x00,0x00,0x0D,0x00,
           0x00,0x38,0x00,0x20,
  ]

  bytes.each_index do |i|
    _rom[0x1fffa0 + i] = bytes[i]
  end

  # Move "Lord" label right
  _rom[0x025192] = 0x00
  _rom[0x025193] = 0x30
  # ...and lower
  _rom[0x02518c] = 0xff
  _rom[0x02518d] = 0xe4
  # Move "Monarch" label left
  _rom[0x0251b4] = 0x00
  _rom[0x0251b5] = 0x4b
  # ... and up
  _rom[0x0251ae] = 0xff
  _rom[0x0251af] = 0xf8
  # Move castle right
  _rom[0x025242] = 0x00
  _rom[0x025243] = 0x10
  # ... and up
  _rom[0x02523c] = 0xff
  _rom[0x02523d] = 0xda


  # Extra space for copyright labels
  _rom[0x024efc] = 0x75
  _rom[0x024efd] = 0x40
  _rom[0x024f02] = 0x86
  _rom[0x024f03] = 0x60
  _rom[0x024f4e] = 0x75
  _rom[0x024f4f] = 0x40
  _rom[0x024f54] = 0x86
  _rom[0x024f55] = 0x60
  _rom[0x01e632] = 0xc4
  _rom[0x01e633] = 0x33
  _rom[0x01e63c] = 0xc4
  _rom[0x01e63d] = 0x67
  _rom[0x01e646] = 0xc4
  _rom[0x01e647] = 0x02
  _rom[0x01e646] = 0xc4
  _rom[0x01e647] = 0x02

  # copyright sprites data
  bytes = [0x00,0x15,
           0x00,0x00,0x0d,0x00, #Repr
           0x00,0x00,0xff,0x84,
           0x00,0x00,0x0d,0x00, # ogram
           0x00,0x08,0x00,0x20,
           0x00,0x00,0x0d,0x00, # med
           0x00,0x10,0x00,0x20,
           0x00,0x00,0x0d,0x00, # game
           0x00,0x18,0x00,0x20,
           0x00,0x00,0x05,0x00, # (c)
           0x00,0x20,0x00,0x30,
           0x00,0x00,0x0d,0x00, # SEGA
           0x00,0x24,0x00,0x10,
           0x00,0x00,0x0d,0x00, # 1994
           0x00,0x2c,0x00,0x48,
           0x00,0x10,0x0d,0x00, # Origi
           0x00,0x96,0xff,0x40,
           0x00,0x00,0x01,0x00, # n
           0x00,0x9e,0x00,0x20,
           0x00,0x00,0x05,0x00, # al
           0x00,0x3c,0x00,0x08,
           0x00,0x00,0x0d,0x00, # game
           0x00,0x18,0x00,0x10,
           0x00,0x00,0x05,0x00, # (c)
           0x00,0x20,0x00,0x30,
           0x00,0x00,0x0d,0x00, # FALC
           0x00,0x40,0x00,0x10,
           0x00,0x00,0x05,0x00, # OM
           0x00,0x48,0x00,0x20,
           0x00,0x00,0x0d,0x00, # 1991
           0x00,0x34,0x00,0x28,
           0x00,0x10,0x0d,0x00, # Tran
           0x00,0x4c,0xff,0x4a,
           0x00,0x00,0x0d,0x00, # slati
           0x00,0x54,0x00,0x20,
           0x00,0x00,0x05,0x00, # on
           0x00,0x5c,0x00,0x20,
           0x00,0x00,0x05,0x00, # (c)
           0x00,0x20,0x00,0x1e,
           0x00,0x00,0x0d,0x00, # NEBU
           0x00,0x60,0x00,0x10,
           0x00,0x00,0x0d,0x00, # LOUS
           0x00,0x68,0x00,0x20,
           0x00,0x00,0x0d,0x00, # 2020
           0x00,0x70,0x00,0x28,
           0x00,0x20,0x0d,0x00,
           0x00,0x00,0xff,0x84,
           0x00,0x20,0x0d,0x00,
           0x00,0x00,0xff,0x84,
  ]

  bytes.each_index do |i|
    _rom[0x025276 + i] = bytes[i]
  end

  # Push start button sprites
  bytes = [0x00,0x03,
           0xff,0xf8,0x0d,0x00,
           0x00,0x06,0xff,0xc4,
           0x00,0x00,0x0d,0x00,
           0x00,0x0e,0x00,0x20,
           0x00,0x00,0x0d,0x00,
           0x00,0x16,0x00,0x20,
           0x00,0x00,0x09,0x00,
           0x00,0x1e,0x00,0x20,
  ]

  bytes.each_index do |i|
    _rom[0x025338 + i] = bytes[i]
    _rom[0x025362 + i] = bytes[i]
  end

end

def mergeASM_Hacks(_rom)
  fixTutorialTimings(_rom)
  hacks_TitleLabels(_rom)

  # Increase tile cache for missions results screen
  _rom[0x1ad42] = 0x72
  _rom[0x1ad43] = 0x4a

  # Set hooks for map list drawing functions
  [0x1b994,0x1ba5e].each do |a|
    _rom[a]     = 0x1e
    _rom[a + 1] = 0x02
  end

  # Map list printing fix
  [0x1b950, 0x1ba6a].each do |a|
    _rom[a]     = 0x12
    _rom[a + 1] = 0x4c
  end

  [0x1b962, 0x1ba82, 0x1bada].each do |a|
    _rom[a]     = 0x00
    _rom[a + 1] = 0xfe
  end

  [0x1b024, 0x1b2ec].each do |a|
    _rom[a]     = 0x15
    _rom[a + 1] = 0x46
  end

  _rom[0x1b908] = 0x00
  _rom[0x1b909] = 0x06

  _rom[0x1b04c] = 0x7e
  _rom[0x1b04d] = 0x06

  # Map name scroll size
  _rom[0x1b06c] = 0xff
  _rom[0x1b06d] = 0x4a # challenge mode
  _rom[0x1b36a] = 0xff
  _rom[0x1b36b] = 0x3a # status screen
  _rom[0x1b254] = 0x3f
  _rom[0x1b255] = 0x02
  _rom[0x1b250] = 0x02
  _rom[0x1b251] = 0xf4

  # Expand name area
  _rom[0x1b9ea] = 0x7a
  _rom[0x1b9eb] = 0x05

  _rom[0x1b946] = 0x00
  _rom[0x1b947] = 0x20

  _rom[0x1b940] = 0x00
  _rom[0x1b941] = 0x09

  _rom[0x1b9e2] = 0x70
  _rom[0x1b9e3] = 0x2a
  _rom[0x1bb5e] = 0x70
  _rom[0x1bb5f] = 0x2b

  # Move tile cache
  _rom[0x1b8aa] = 0x12
  _rom[0x1b8ab] = 0x00
  # Increase tile cache size
  _rom[0x1b8ae] = 0x02
  _rom[0x1b8af] = 0x70

  # Expand ingame tile cache
  _rom[0xd700] = 0xa4
  _rom[0xd701] = 0x00
  _rom[0xd704] = 0x00
  _rom[0xd705] = 0xa0

  # Align "complete" label on chapter intermission screen
  _rom[0x1db9c] = 0x70
  _rom[0x1db9d] = 0x10
  _rom[0x1db62] = 0x70
  _rom[0x1db63] = 0x0f

  # Mission replay days difference tile cache position
  _rom[0x1aeac] = 0xaa
  _rom[0x1aead] = 0x00

  # Cutscene 3rd text line cleanup
  _rom[0x1f79a] = 0x00
  _rom[0x1f79b] = 0x06

  # "Cutscene/Ending" main menu label VRAM tile position fix
  _rom[0x1ca52] = 0x01
  _rom[0x1ca53] = 0xb0
  _rom[0x1c4a8] = 0x01
  _rom[0x1c4a9] = 0xb0

  # "Yes/no" main menu label VRAM tile position"
  _rom[0x1c454] = 0x01
  _rom[0x1c455] = 0x70
  _rom[0x1cb2c] = 0x01
  _rom[0x1cb2d] = 0x70

  # Fix main menu label offsets in tile cache
  _rom[0x1c288] = 0x00
  _rom[0x1c289] = 0x20

  # Fix next level label transformation
  _rom[0x1be8c] = 0x1b
  _rom[0x1be8d] = 0x00

  # Fix challenge mode ending
  # Tile cache start and size
  _rom[0x1dc38] = 0x30
  _rom[0x1dc39] = 0x00
  _rom[0x1dc3c] = 0x04
  _rom[0x1dc3d] = 0x80
  # Screen clearing
  _rom[0x1dd78] = 0x70
  _rom[0x1dd79] = 0x00
  _rom[0x1dd7a] = 0x76
  _rom[0x1dd7b] = 0x26

  # Static strings - increase limit to 16 characters
  _rom[0xe9e8] = 0xe9
  _rom[0xe9e9] = 0x48

  addrs = [0xe26c, 0xc5bc, 0xc5d6, 0xc26a]
  addrs.each do |addr|
    _rom[addr + 0] = 0xe9
    _rom[addr + 1] = 0x4f
    _rom[addr + 2] = 0xde
    _rom[addr + 3] = 0x46
  end

  _rom[0x732a] = 0xe9
  _rom[0x732b] = 0x48
  _rom[0x732c] = 0xd0
  _rom[0x732d] = 0x41

  # Print op_print_variable opcode with script-text.asm (BSR redirect code)
  _rom[0x1041a] = 0xfb
  _rom[0x1041b] = 0xb0

  # Move record fix label
  bytes = [0x2F,0x3D,
           0x06,0x01,0xFF,0xFF,0xCE,0x74,
           0x61,0xB1,0xFA,0x3C,0x2D,0x30,
           0x06,0x01,0xFF,0xFF,0xCE,0x75,
           0x3E,0x2F,0x23,0x00]
  bytes.length.times do |i|
    _rom[0x1E7F4B + i] = bytes[i]
  end

  # "Now Challenging" label fix
  label = " Now Playing \0".bytes
  label.length.times do |i|
    _rom[0x246e6 + i] = label[i]
  end

  # Skip region check
  _rom[0x6d64] = 0x4e
  _rom[0x6d65] = 0x75

  # Fix 0x03 action (don't allow skipping wait action)
  6.times do |i|
    _rom[0x010044 + 2*i] = 0x4e
    _rom[0x010045 + 2*i] = 0x71
  end

  # Skip checksum check
  skip = [0x60, 0x00, 0x00, 0x1e] + Array.new(0x1c, 0xff)
  skip.size.times do |t|
    _rom[t + 0x6940] = skip[t]
    _rom[t + 0x6b40] = skip[t]
  end
end

def calculateChecksum(_rom)
  debugPrint "Calculating checksum..."
  checksum = 0
  (0x200..Const::ROM_MaxAddr).each_slice(2) do |i|
    checksum += _rom[i[0]]*0x100 + _rom[i[1]]

  end
  checksum &= 0xffff
  checksumBytes = Util.numToBytes(checksum, 2, false)
  checksumBytes.length.times do |i|
    _rom[0x00018e + i] = checksumBytes[i]
  end
  debugPrint "Checksum = %04x" % checksum
end

def patchROM
  newFile = @patchedRom

  mergeASM_Hacks(newFile)
  patchFont(newFile)
  patchASM(newFile)

  resRepacker = ResEncoder.new(newFile)
  resRepacker.repackData()

  applyBinaryPatches(newFile)

  Util.new(newFile)
  if Configuration::Mode != "import"
    export = DataExporter.new(@db, Paths::PTRS_CSV, @romBytes)
    export.exportData()
  end

  if Configuration::Mode != "export"
    import = DataImporter.new(@db, Paths::TRANSLATION_EN_US_DB, newFile)
    import.importData

    calculateChecksum(newFile)

    IO.binwrite(Paths::PATCHED_ROM, newFile.pack('c*'))
  end

end

def main()
  start_time = Time.now

  patchROM

  end_time = Time.now
  puts "Done!"
  puts "Running time: " + (end_time - start_time).to_s + " seconds."
end

main()