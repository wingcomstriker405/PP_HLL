dofile "C:/Users/Admin/Desktop/HighLevelLanguage/HLL Scripts/Deconstructor/Deconstructor.lua"
dofile "C:/Users/Admin/Desktop/HighLevelLanguage/HLL Scripts/Interpreter/Interpreter.lua"

local user_code1 = {
    "def main()",
    "   vector1 = vec(5, 5, 5)",
    "   vector2 = scale(dir(), 5)",
    "   vector3 = add(vector1, vector2)",
    "   vector4 = sub(vec(1, 0, 0), vec(0, 1, 0))",
    "   print(vector1, vector2, vector3, vector4)",
    "   print(cross([1, 0, 0], [0, 1, 0]))",
    "end",
    "main()"
}

local user_code2 = {
    "def main()",
    "   y = 10",
    "   if 256 == 1 << 8",
    "       x = 100",
    "       y = x / 2",
    "   end",
    "   print(y)",
    "end",
    "",
    "main()"
}

local user_code3 = {
    "def main()",
    "   for i = 1, i < 10, i = i + 1",
    "      print(i)",
    "   end",
    "end",
    "",
    "main()"
}

local user_code4 = {
    "def main()",
    "   x = 0",
    "   while x < 10",
    "       x = x + 1",
    "       print(x)",
    "   end",
    "end",
    "",
    "main()"
}

local user_code5 = {
    "def main()",
    "   elements = [3, 2, 1, 2, 3]",
    "   for i = 1, i <= 10, i = i + 1",
    "       print(i)",
    "       if i == 5",
    "           print(1111)",
    "       elseif i == 6",
    "           print(2222)",
    "       else",
    "           print(3333)",
    "       end",
    "   end",
    "end",
    "",
    "main()"
}

local user_code6 = {
    "def main()",
    "   v1 = vec(10, 0, 0)",
    "   v2 = vec(10, 0, 10)",
    "   v3 = cross(v1, v2)",
    "   print(v3)",
    "   print(normalize(v3))",
    "   print(deg(angle(v3, v2)))",
    "   print(deg(angle(v1, v2)))",
    "end",
    "",
    "main()"
}

local user_code9 = {
    "list = []",
    "",
    "def main()",
    "   for i = 0, i <= 10, i = i + 1",
    "       list[i] = 2 ^ i",
    "   end",
    "end",
    "",
    "main()",
    "print(list)",
    "print(exp(1))"
}

local user_code10 = {
    "def main()",
    "   mykeys = ['erster', 'zweiter', 'dritter']",
    "   list = []",
    "   for i = 1, i <= size(mykeys), i = i + 1",
    "       list[mykeys[i]] = random()",
    "   end",
    "   print(list)",
    "end",
    "",
    "main()"
}

local user_code = {
    "def main()",
    "   test = none",
    "   print(type(test))",
    "   print(test)",
    "   if test == none",
    "       print('variable is none')",
    "   end",
    "end",
    "",
    "main()"
}

function main()
    local deconstructor = Deconstructor.new(user_code)
    local code = deconstructor:deconstruct()
     if true then
        print("-----[ CODE ]-----")
        for i = 1, #code, 1 do
            print(i - 8, code[i])
        end
    end
    
    local iterpreter  = Interpreter.new(code)
    local finished = false
    repeat
        finished = iterpreter:evaluateNextLine()
    until finished
    --iterpreter:printVariables()
end

main()