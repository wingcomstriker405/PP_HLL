dofile "C:/Users/Admin/Desktop/HighLevelLanguage/HLL Scripts/Deconstructor/Deconstructor.lua"
dofile "C:/Users/Admin/Desktop/HighLevelLanguage/HLL Scripts/Interpreter/Interpreter.lua"
dofile "C:/Users/Admin/Desktop/HighLevelLanguage/HLL Scripts/Executor/Files.lua"

function file_exists(file)
  local f = io.open(file, "rb")
  if f then f:close() end
  return f ~= nil
end

function lines_from(file)
  if not file_exists(file) then return {} end
  lines = {}
  for line in io.lines(file) do 
    lines[#lines + 1] = line
  end
  return lines
end

function main()
    local file = 'C:/Users/Admin/Desktop/HighLevelLanguage/HLL Scripts/Data/code.txt'
    local usercode = lines_from(file)
    if #usercode > 0 then
        local deconstructor = Deconstructor.new(usercode)
        local code = deconstructor:deconstruct()
        if true then
            file = io.open('C:/Users/Admin/Desktop/HighLevelLanguage/HLL Scripts/Data/deconstructed.txt', 'w')
            io.output(file)
            for i = 1, #code, 1 do
                io.write(code[i] .. '\n')
            end
            io.close(file)
            print("written to file")
        end
        if not deconstructor.fatal_error then
            local iterpreter  = Interpreter.new(code, files)
            local finished = false
            repeat
                finished = iterpreter:evaluateNextLine()
            until finished
        end
    end
end

main()