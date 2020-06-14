ExpressionDeconstructor = {}

function ExpressionDeconstructor.new()
    local obj = {}
    for k, v in pairs(ExpressionDeconstructor) do
        obj[k] = v
    end
    return obj
end

function ExpressionDeconstructor.getTempPrefix(self)
    self.temps = self.temps + 1
    return "t_" .. self.temps
end

function ExpressionDeconstructor.getArgumentPrefix(self)
    self.arguments = self.arguments + 1
    return "a_" .. self.arguments
end

function ExpressionDeconstructor.getKeyPrefix(self)
    self.keys = self.keys + 1 
    return "k_" .. self.keys
end

function ExpressionDeconstructor.getVariablePrefix(self)
    return "v_"
end

function ExpressionDeconstructor.getListPrefix(self)
    self.lists = self.lists + 1
    return "l_" .. self.lists
end

----------[ UTIL FUNCTIONS ]----------
function ExpressionDeconstructor.calculateRest(self)
    self.rest = self.expression:sub(self.index)
end

function ExpressionDeconstructor.increaseIndex(self, str, offset)
    if offset then
        self.index = self.index + offset
    end
    self.index = self.index + #str
end

function ExpressionDeconstructor.getValueObject(self, value_type, value)
    local obj = {}
    obj.vt = value_type
    obj.v = value
    return obj
end

function ExpressionDeconstructor.deconstruct(self, expression)
    self:setup(expression)
    self:deconstructExpression()
    return self:combineCode()
end


function ExpressionDeconstructor.setup(self, expression)
    self.expression = expression
    self.index = 1
    self.length = expression:len()
    self.rest = ""

    self.compiled = {}
    self.stack = {}
    self.temps = 0
    self.arguments = 0
    self.keys = 0
    self.lists = 0
end

function ExpressionDeconstructor.combineCode(self)
    local combined = {}
    for i = 1, #self.compiled, 1 do
        table.insert(combined, "")
        for k = 1, #self.compiled[i], 1 do
            combined[#combined] = combined[#combined] .. self.compiled[i][k].v
        end
    end
    return combined
end

----------[ IDENTIFICATION FUNCTIONS ]----------
function ExpressionDeconstructor.nextIsVariable(self)
    return self.rest:match("^[A-Za-z_][A-Za-z0-9_]*.*")
end

function ExpressionDeconstructor.nextIsFunctionCall(self)
    return self.rest:match("^[A-Za-z_][A-Za-z0-9_]*%(.+")
end

function ExpressionDeconstructor.nextIsListCall(self)
    return self.rest:match("^[A-Za-z_][A-Za-z0-9_]*%[.+")
end

function ExpressionDeconstructor.nextIsNumber(self)
    return self.rest:match("^%d+.*")
end

function ExpressionDeconstructor.nextIsBits(self)
    return self.rest:match("^b'[01]*'.*")
end

function ExpressionDeconstructor.nextIsHex(self)
    return self.rest:match("^0x[0-9a-f]+.*")
end

function ExpressionDeconstructor.nextIsOperator(self)
    return self.rest:match("^[%^%+%-%*%%%/%%%&%|%<%>%=]+.*")
end

function ExpressionDeconstructor.nextIsString(self)
    return self.rest:match("^'.+")
end

function ExpressionDeconstructor.nextIsNested(self)
    return self.rest:match("^%(.+")
end

function ExpressionDeconstructor.nextIsList(self)
    return self.rest:match("^%[.+")
end

----------[ EXTRACTION FUNCTIONS ]----------
function ExpressionDeconstructor.extractFunctionCall(self)
    local value = self.rest:match("^[A-Za-z_][A-Za-z0-9_]*")
    self:increaseIndex(value, 1)
    local temp_name = self:getTempPrefix()
    local arg_list = self:getArgumentPrefix()
    table.insert(self.stack[#self.stack], self:getValueObject("temporary_variable", temp_name))
    local argument_list = {self:getValueObject("list", arg_list), self:getValueObject("err", " "), self:getValueObject("operator", "="), self:getValueObject("err", " "), self:getValueObject("err", "[")}
    self:deconstructExpression(")")
    local parts = table.remove(self.compiled, #self.compiled)
    if #parts > 0 then
        local name = self:getTempPrefix()
        table.insert(argument_list, self:getValueObject("temporary_variable", name))
        table.insert(self.compiled, {self:getValueObject("temporary_variable", name), self:getValueObject("operator", "="), self:getValueObject("err", " ")})
        for i = 1, #parts, 1 do
            if parts[i].vt == "err" and parts[i].v == "," then
                name = self:getTempPrefix()
                table.insert(argument_list, parts[i])
                table.insert(argument_list, self:getValueObject("temporary_variable", name))
                table.insert(self.compiled, {self:getValueObject("temporary_variable", name), self:getValueObject("operator", "=")})
            else
                table.insert(self.compiled[#self.compiled], parts[i])
            end
        end
    end
    table.insert(argument_list, self:getValueObject("err", "]"))
    table.insert(self.compiled, argument_list)
    table.insert(self.compiled, {self:getValueObject("function_call", "function_call"), self:getValueObject("err", " "), self:getValueObject("function_name", value), self:getValueObject("err", " "), self:getValueObject("list", arg_list)})
    table.insert(self.compiled, {self:getValueObject("temporary_variable", temp_name), self:getValueObject("err", " "), self:getValueObject("operator", "="), self:getValueObject("err", " "), self:getValueObject("temporary_variable", "t_return")})
end

function ExpressionDeconstructor.extractListCall(self)
    local value = self.rest:match("^[A-Za-z_][A-Za-z0-9_]*")
    local list = self:getListPrefix()
    table.insert(self.stack[#self.stack], self:getValueObject("list_call", self:getVariablePrefix() .. value))
    self:increaseIndex(value)
    self:calculateRest()
    local char = self.rest:sub(1, 1)
    while char == "[" do
        table.insert(self.stack[#self.stack], self:getValueObject("err", "["))
        self:increaseIndex("", 1)
        
        local key = self:getKeyPrefix()
        table.insert(self.stack[#self.stack], self:getValueObject("temporary_variable", key))
        self:deconstructExpression("]", {self:getValueObject("temprary_variable", key), self:getValueObject("err", " "), self:getValueObject("operator", "="), self:getValueObject("err", " ")})
        
        table.insert(self.stack[#self.stack], self:getValueObject("err", "]"))
        self:calculateRest()
        char = self.rest:sub(1, 1)
    end
    --print("LIST CALL: ", value)
end

function ExpressionDeconstructor.extractVariable(self)
    local value = self.rest:match("^[A-Za-z_][A-Za-z0-9_]*")
    self:increaseIndex(value)
    if value == "true" or value == "false" then
        table.insert(self.stack[#self.stack], self:getValueObject("boolean", value))
        --print("BOOLEAN: ", value)
    else
        table.insert(self.stack[#self.stack], self:getValueObject("user_variable", self:getVariablePrefix() .. value))
        --print("VARIABLE: ", value)
    end
end

function ExpressionDeconstructor.extractNumber(self)
    local value = self.rest:match("^%d+%.?%d*")
    table.insert(self.stack[#self.stack], self:getValueObject("number", value))
    self:increaseIndex(value)
    --print("NUMBER: ", value)
end

function ExpressionDeconstructor.extractHex(self)
    local value = self.rest:match("^0x[0-9a-f]+")
    table.insert(self.stack[#self.stack], self:getValueObject("hex", value))
    self:increaseIndex(value)
    --print("HEX: ", value)
end

function ExpressionDeconstructor.extractBoolean(self)
    local value = self.rest:match("^true.*") or self.rest:match("^false.*")
    self:increaseIndex(value)
    table.insert(self.stack[#self.stack], self:getValueObject("boolean", value))
    --print("BOOLEAN: ", value)
end

function ExpressionDeconstructor.extractOperator(self)
    local value = self.rest:match("^[%^%+%-%*%%%/%%%&%|%<%>%=]+")
    table.insert(self.stack[#self.stack], self:getValueObject("operator", value))
    self:increaseIndex(value)
    --print("OPERATOR: ", value)
end

function ExpressionDeconstructor.extractString(self)
    local extracted = ""
    local unfinished = true
    for i = 2, #self.rest, 1 do
        local char = self.rest:sub(i, i)
        if char == "\\" then
            i = i + 1
        elseif char == "'" then
            unfinished = false
            extracted = self.rest:sub(1, i)
            break
        end
    end
    if unfinished then
        print("ERROR: UNCLOSED STRING")
    else
        --print("STRING: ", extracted)
        table.insert(self.stack[#self.stack], self:getValueObject("string", extracted))
    end
    self:increaseIndex(extracted)
end

function ExpressionDeconstructor.extractBits(self)
    local value = self.rest:match("^b'[01]+'")
    self:increaseIndex(value)
    table.insert(self.stack[#self.stack], self:getValueObject("bits", value))
    --print("BITS: ", value)
end

function ExpressionDeconstructor.extractNested(self)
    local temp_name = self:getTempPrefix()
    self:increaseIndex("", 1)
    table.insert(self.stack[#self.stack], self:getValueObject("temporary_variable", temp_name))
    self:deconstructExpression(")", {self:getValueObject("temporary_variable", temp_name), self:getValueObject("err", " "), self:getValueObject("operator", "="), self:getValueObject("err", " ")})
end

function ExpressionDeconstructor.extractList(self)
    table.insert(self.stack[#self.stack], self:getValueObject("err", "["))
    local char = self.rest:sub(1, 1)
    self:increaseIndex("", 1)
    self:deconstructExpression("]")
    local list_parts = table.remove(self.compiled)
    if #list_parts > 0 then
        local name = self:getTempPrefix()
        table.insert(self.stack[#self.stack], self:getValueObject("err", name))
        table.insert(self.stack, {self:getValueObject("err", name), self:getValueObject("err", " "), self:getValueObject("operator", "=")})
        for i = 1, #list_parts, 1 do
            local ele = list_parts[i]
            if ele.vt == "err" and ele.v == "," then
                name = self:getTempPrefix()
                local removed = table.remove(self.stack, #self.stack)
                table.insert(self.compiled, removed)
                table.insert(self.stack[#self.stack], ele)
                table.insert(self.stack[#self.stack], self:getValueObject("err", name))
                table.insert(self.stack, {self:getValueObject("err", name), self:getValueObject("err", " "), self:getValueObject("operator", "=")})
            else
                table.insert(self.stack[#self.stack], ele)
            end
        end
        local removed = table.remove(self.stack, #self.stack)
        table.insert(self.compiled, removed)
        table.insert(self.stack[#self.stack], self:getValueObject("err", "]"))
    end
end

----------[ DECONSTRUCTION FUNCTIONS ]----------
function ExpressionDeconstructor.deconstructExpression(self, stop, base)
    if base then
        table.insert(self.stack, base)
    else
        table.insert(self.stack, {})
    end
    while self.index <= self.length do
        -- refresh the rest value
        self:calculateRest()
        if self:nextIsFunctionCall() then
            self:extractFunctionCall()
        elseif self:nextIsListCall() then
            self:extractListCall()
        elseif self:nextIsBits() then
            self:extractBits()
        elseif self:nextIsList() then
            self:extractList()
        elseif self:nextIsHex() then
            self:extractHex()
        elseif self:nextIsNumber() then
            self:extractNumber()
        elseif self:nextIsOperator() then
            self:extractOperator()
        elseif self:nextIsVariable() then
            self:extractVariable()
        elseif self:nextIsString() then
            self:extractString()
        elseif self:nextIsNested() then
            self:extractNested()
        else
            self:increaseIndex("", 1)
            if self.rest:sub(1, 1) == stop then
                local last = table.remove(self.stack, #self.stack)
                table.insert(self.compiled, last)
                return
            else
                table.insert(self.stack[#self.stack], self:getValueObject("err", self.rest:sub(1, 1)))
            end
        end
    end
    local last = table.remove(self.stack, 1)
    if #self.stack > 0 then
        print("ERROR: MISSMATCHING CLOSING")
        --print(self.expression)
    end
    table.insert(self.compiled, last)
end

--local deconstructed = massDeconstructor(c)
--print()
--ExpressionDeconstructor.printCode(ExpressionDeconstructor.combineCode(deconstructed))