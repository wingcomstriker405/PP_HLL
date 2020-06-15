dofile "C:/Users/Admin/Desktop/HighLevelLanguage/HLL Scripts/Deconstructor/ExpressionDeconstructor.lua"
Deconstructor = {}

function Deconstructor.new(code)
    local obj = {}
    for k, v in pairs(Deconstructor) do
        obj[k] = v
    end
    obj.code = code
    obj.generated_code = {}
    obj.environments = {}
    
    obj.function_signature = "^def%s+[A-Za-z_][A-Za-z0-9_]*%(.*%)$"
    obj.for_loop = "^for%s+.+,.+,.+$"
    obj.while_loop = "^while%s+.+$"
    obj.if_statement = "^if%s+.+"
    obj.block_end = "^end$"
    obj.elseif_statement = "^elseif%s+.+$"
    obj.else_statement = "^else$"
    obj.return_statement = "^return.*$"
    obj.comment = "^#.+$"

    obj.line = ""
    obj.index = 1

    obj.registered_functions = {}
    obj.generated = {}
    obj.block_stack = {}
    obj.exp_deconstructor = ExpressionDeconstructor.new()
    obj.outside = {}
    return obj
end

function Deconstructor.deconstruct(self)
    for i = 1, #self.code, 1 do
        self.index = i
        self.line = self:trim(self.code[i])
        if self:lineIs(self.comment) then
        elseif self:lineIs(self.function_signature) then
            self:compileFunctionSiganture()
        elseif self:lineIs(self.for_loop) then
            self:compileForLoop()
        elseif self:lineIs(self.while_loop) then
            self:compileWhileLoop()
        elseif self:lineIs(self.if_statement) then
            self:compileIfStatement()
        elseif self:lineIs(self.elseif_statement) then
            self:compileElseIfStatement()
        elseif self:lineIs(self.else_statement) then
            self:compileElseStatement()
        elseif self:lineIs(self.block_end) then
            self:compileEnd()
        elseif self:lineIs(self.return_statement) then
            self:compileReturn()
        else
            if self.line ~= "" then
                local exp_code = self.exp_deconstructor:deconstruct(self.line)
                if #self.block_stack == 0 then
                    for i = 1, #exp_code, 1 do
                        table.insert(self.outside, exp_code[i])
                    end
                else
                    for i = 1, #exp_code, 1 do
                        table.insert(self.generated, exp_code[i])
                    end
                end
            end
        end
    end
    return self:combineToFullCode()
end

function Deconstructor.combineToFullCode(self)
    local combined = {}
    table.insert(combined, "OUTSIDE")
    for i = 1, #self.outside, 1 do
        table.insert(combined, self.outside[i])
    end
    table.insert(combined, "FUNCTIONS")
    for i = 1, #self.registered_functions, 1 do
        table.insert(combined, self.registered_functions[i])
    end
    table.insert(combined, "CODE")
    for i = 1, #self.generated, 1 do
        table.insert(combined, self.generated[i])
    end
    return combined
end

function Deconstructor.lineIs(self, regex)
    return self.line:match(regex)
end

function Deconstructor.compileFunctionSiganture(self)
    local name = self.line:match("^def%s+([A-Za-z_][A-Za-z0-9_]*)%(.+")
    local parameters = ""
    for parameter in self.line:match(".+%((.*)%)"):gmatch("[A-Za-z_][A-Za-z0-9_]*") do
        if self:trim(parameter) ~= "" then
            parameters = parameters .. " v_" .. self:trim(parameter)
        end
    end
    parameters = self:trim(parameters)
    table.insert(self.registered_functions, name .. " " .. parameters .. " >> " .. (#self.generated + 1))
    table.insert(self.block_stack, {"function", #self.generated + 1})
    table.insert(self.generated, "push function env")
end

function Deconstructor.compileForLoop(self)
    --add compilation
    local pre = self:trim(self.line:match("for%s+(.+),.+,.+"))
    local pre_code = self.exp_deconstructor:deconstruct(pre) --COMPILE CODE HERE
    local condition = self:trim(self.line:match("for%s+.+,(.+),.+"))
    local condition_code = self.exp_deconstructor:deconstruct(condition) --COMPILE CODE HERE
    local past = self:trim(self.line:match("for%s+.+,.+,(.+)"))
    local past_code = self.exp_deconstructor:deconstruct(past) --COMPILE CODE HERE

    table.insert(self.generated, "push loop env")

    local pre_line = #self.generated + 1
    for i = 1, #pre_code, 1 do
        table.insert(self.generated, pre_code[i])
    end
    table.insert(self.generated, "jumpr " .. (#past_code + 1))
    local past_line = #self.generated + 1
    for i = 1, #past_code, 1 do
        table.insert(self.generated, past_code[i])
    end

    local condition_line = #self.generated + 1
    for i = 1, #condition_code, 1 do
        table.insert(self.generated, condition_code[i])
    end
    self.generated[#self.generated] = "t_condition = " .. self.generated[#self.generated]
    table.insert(self.generated, "if t_condition >> ")
    table.insert(self.block_stack, {"loop", #self.generated, pre_line, condition_line, past_line})
end

function Deconstructor.compileWhileLoop(self)
    table.insert(self.generated, "push loop env")

    local condition = self.line:match("^while%s+(.+)$")
    local condition_line = #self.generated + 1
    local condition_code = self.exp_deconstructor:deconstruct(condition) --COMPILE CODE HERE
    for i = 1, #condition_code, 1 do
        table.insert(self.generated, condition_code[i])
    end
    self.generated[#self.generated] = "t_condition = " .. self.generated[#self.generated]
    table.insert(self.generated, "if t_condition >> ")
    table.insert(self.block_stack, {"loop", #self.generated, 0, 0, condition_line})
end

function Deconstructor.compileIfStatement(self)
    local condition = self:trim(self.line:match("if%s+(.+)$"))
    local condition_code = self.exp_deconstructor:deconstruct(condition) --COMPILE CODE HERE
    local condition_line = #self.generated + 1
    for i = 1, #condition_code, 1 do
        table.insert(self.generated, condition_code[i])
    end
    self.generated[#self.generated] = "t_condition = " .. self.generated[#self.generated]
    table.insert(self.generated, "if t_condition >> ")
    table.insert(self.block_stack, {"if", #self.generated, condition_line})
    table.insert(self.generated, "push if env")
end

function Deconstructor.compileElseIfStatement(self)
    if self.block_stack[#self.block_stack][1] == "if" or self.block_stack[#self.block_stack][1] == "elseif" then
        self.block_stack[#self.block_stack][4] = #self.generated + 1
        table.insert(self.generated, "pop " .. self.block_stack[#self.block_stack][1] .. " env")
        table.insert(self.generated, "jumpr ")
        local condition = self:trim(self.line:match("elseif%s+(.+)$"))
        local condition_code = self.exp_deconstructor:deconstruct(condition)
        local condition_line = #self.generated + 1
        for i = 1, #condition_code, 1 do
            table.insert(self.generated, condition_code[i])
        end
        self.generated[#self.generated] = "t_condition = " .. self.generated[#self.generated]
        table.insert(self.generated, "if t_condition >> ")
        table.insert(self.block_stack, {"elseif", #self.generated, condition_line})
        table.insert(self.generated, "push elseif env")
    else
        print("ERROR (" .. self.index .. "): " .. self.line)
        print(">> elseif without if")
    end
end

function Deconstructor.compileElseStatement(self)
    if self.block_stack[#self.block_stack][1] == "if" or self.block_stack[#self.block_stack][1] == "elseif" then
        self.block_stack[#self.block_stack][4] = #self.generated + 1
        table.insert(self.generated, "pop " .. self.block_stack[#self.block_stack][1] .. " env")
        table.insert(self.generated, "jumpr ")
        table.insert(self.generated, "else")
        table.insert(self.generated, "push else env")
        table.insert(self.block_stack, {"else", #self.generated, #self.generated - 1})
    else
        print("ERROR (" .. self.index .. "): " .. self.line)
        print(">> else without if or elseif")
    end
end

function Deconstructor.compileEnd(self)
    if #self.block_stack > 0 then
        if self.block_stack[#self.block_stack][1] == "if" then
            local block = table.remove(self.block_stack, #self.block_stack)
            table.insert(self.generated, "pop if env")
            self.generated[block[2]] = self.generated[block[2]] .. (#self.generated + 1)

        elseif self.block_stack[#self.block_stack][1] == "else" or self.block_stack[#self.block_stack][1] == "elseif" then
            table.insert(self.generated, "pop " .. self.block_stack[#self.block_stack][1] .. " env")
            local prev_pos = #self.generated + 1
            local after = #self.generated + 1
            repeat
                local block = table.remove(self.block_stack, #self.block_stack)
                if block[1] ~= "else" then
                    self.generated[block[2]] = self.generated[block[2]] .. prev_pos
                end
                if block[1] ~= "if" then
                    self.generated[block[3] - 1] = self.generated[block[3] - 1] .. " " .. (after - (block[3] - 1))
                end
                prev_pos = block[3]
            until block[1] == "if"

        elseif self.block_stack[#self.block_stack][1] == "loop" then
            local block = table.remove(self.block_stack, #self.block_stack)
            table.insert(self.generated, "jumpr " .. (block[5] - #self.generated - 1))
            table.insert(self.generated, "pop loop env")
            self.generated[block[2]] = self.generated[block[2]] .. #self.generated

        elseif self.block_stack[#self.block_stack][1] == "function" then
            table.remove(self.block_stack, #self.block_stack)
            table.insert(self.generated, "pop function env")
        end
    else
        print("ERROR (" .. self.index .. "): " .. self.line)
        print(">> trying to closes non existing block!")
    end
end

function Deconstructor.compileReturn(self)
    local data = self.line:match("^return%s*(.+)")
    if data then
        local code = self.exp_deconstructor:deconstruct("(" .. data .. ")")
        for i = 1, #code, 1 do
            if i == #code then
                table.insert(self.generated, "t_return = " .. code[i])
            else
                table.insert(self.generated, code[i])
            end
        end
    end
    table.insert(self.generated, "return")
end

function Deconstructor.trim(self, line)
    return (line:gsub("^%s+", ""):gsub("%s+$", ""))
end