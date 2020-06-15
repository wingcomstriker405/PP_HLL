Interpreter = {}
Interpreter.fatal_error = false
Interpreter.ooe = {"^","%","/","*","+","-",">>","<<", "++", "<-", "&","|", "<", ">", "<=", ">=", "==", "!=","&&","||", "+=", "-=", "/=", "*=", "%=", "^=", "="}
Interpreter.hex_abc = {"0","1","2","3","4","5","6","7","8","9","a","b","c","d","e","f"}
Interpreter.system_functions = {"num", "str", "vec", "add", "sub", "dot", "cross", "angle", "scale", "length", "normalize", "combine", "size", "keys", "values", "in", "out", "print", "pos", "dir", "vel", "min", "max", "abs", "cos", "sin", "tan", "acos", "asin", "atan", "random", "deg", "rad", "floor", "ceil", "exp", "seed", "time", "type", "open", "next", "line", "stream", "clear", "filetype", "filename", "current", "write", "insert", "remove", "new", "exists", "matches", "substring", "replace", "char", "input"}

function Interpreter.new(raw_code, files)
    math.randomseed(os.time())
    math.random(); math.random(); math.random()
    
    local obj = {}
    for k, v in pairs(Interpreter) do
        obj[k] = v
    end
    obj.files = files
    obj.outside = {}
    obj.signatures = {}
    obj.code = {}
    local mode = ""
    for i = 1, #raw_code, 1 do
        if raw_code[i] == "OUTSIDE" then
            mode = "OUTSIDE"
        elseif raw_code[i] == "FUNCTIONS" then
            mode = "FUNCTIONS"
        elseif raw_code[i] == "CODE" then
            mode = "CODE"
        else
            if mode == "OUTSIDE" then
                table.insert(obj.outside, raw_code[i])
            elseif mode == "FUNCTIONS" then
                local signature = {}
                signature.name = raw_code[i]:match("^([A-Za-z_][A-Za-z0-9_]*).+")
                signature.parameters = {}
                local raw_parameters = raw_code[i]:match("^[A-Za-z_][A-Za-z0-9_]*%s+(.+)%s+>>.+")
                if raw_parameters then
                    for parameter in raw_parameters:gmatch("[A-Za-z_][A-Za-z0-9_]*") do
                        table.insert(signature.parameters, parameter)
                    end
                end
                signature.line = tonumber(raw_code[i]:match(".+>>(.+)$"))
                table.insert(obj.signatures, signature)
            elseif mode == "CODE" then
                table.insert(obj.code, raw_code[i])
            end
        end
    end
    
    obj.envs = {{index = 0, mode = "outside"}}
    
    
    obj.scopes = {}
    obj.global_variables = {}
    obj.temp_variables = {}
    obj.arg_lists = {}
    obj.keys = {}
    
    return obj
end

function Interpreter.numberToHex(self, number)
    local value = ""
    while number > 0 do
        local rem = number % 16
        value = self.hex_abc[rem + 1] .. value
        number = math.floor(number / 16)
    end
    return "0x" .. value
end

function Interpreter.hexToNumber(self, string)
    local number = 0
    local hex_string = string:sub(3)
    for i = 1, #hex_string, 1 do
        local char = hex_string:sub(i, i)
        for k = 1, #self.hex_abc, 1 do
            if char == self.hex_abc[k] then
                number = number + (k - 1) * 16 ^ (#hex_string - i)
            end
        end
    end
    return number
end

function Interpreter.calculateRest(self)
    self.rest = self.expression:sub(self.index)
end

function Interpreter.increaseIndex(self, str, offset)
    if offset then
        self.index = self.index + offset
    end
    self.index = self.index + #str
end

function Interpreter.getValueObject(self, value_type, value, keys)
    local obj = {}
    obj.vt = value_type
    obj.v = value
    obj.keys = keys or {}
    return obj
end

function Interpreter.nextIsIdentifier(self)
    return self.rest:match("^[A-Za-z_][A-Za-z0-9_]*.*")
end

function Interpreter.nextIsOperator(self)
    return self.rest:match("^[%^%+%-%*%/%%%&%|%?%!%<%>%=%:]+.+")
end

function Interpreter.nextIsNumber(self)
    return self.rest:match("^-?%d+%.?%d*.*")
end

function Interpreter.nextIsListCall(self)
    return self.rest:match("^[A-Za-z_][A-Za-z0-9_]*%[")
end

function Interpreter.nextIsListConstruction(self)
    return self.rest:match("^%[.+")
end

function Interpreter.nextIsString(self)
    return self.rest:match("^'.+")
end

------------------------------
function Interpreter.extractIdentifier(self)
    local value = self.rest:match("^[A-Za-z_][A-Za-z0-9_]*")
    if value == "true" or value == "false" then
        table.insert(self.parts, self:getValueObject("boolean", value == "true"))
    elseif value == "none" then
        table.insert(self.parts, self:getValueObject("none", "none"))
    else
        local variable_type = ""
        if value:match("^v_.+") then
            variable_type = "user_variable"
        elseif value:match("^t_.+") then
            variable_type = "temporary_variable"
        elseif value:match("^a_.+") then
            variable_type = "argument_list"
        elseif value:match("^k_.+") then
            variable_type = "key_variable"
        end
        table.insert(self.parts, self:getValueObject(variable_type, value))
    end
    self:increaseIndex(value)
end

function Interpreter.extractOperator(self)
    local value = self.rest:match("^[%^%+%-%*%/%%%&%|%?%!%<%>%=%:]+")
    table.insert(self.parts, self:getValueObject("operator", value))
    self:increaseIndex(value)
end

function Interpreter.extractNumber(self)
    local value = self.rest:match("^-?%d+%.?%d*")
    table.insert(self.parts, self:getValueObject("number", tonumber(value)))
    self:increaseIndex(value)
end

function Interpreter.extractListConstruction(self)
    local save = self.parts
    self.parts = {}
    self:increaseIndex("", 1)
    self:deconstruct("]")
    local list_value = {}
    local cache = {}
    local counter = 1
    for i = 1, #self.parts, 1 do
        if self.parts[i].vt == "err" and self.parts[i].v == "," then
            if #cache == 1 then
                list_value[counter] = self:getVariable(cache[1])
                counter = counter + 1
                cache = {}
            elseif #cache == 3 then
                list_value[cache[1].v] = self:getVariable(cache[3])
            end
        elseif not (self.parts[i].vt == "err" and self.parts[i].v == " ") then
            table.insert(cache, self.parts[i])
        end
    end
    if #cache == 1 then
        list_value[counter] = self:getVariable(cache[1])
        counter = counter + 1
    elseif #cache == 3 then
        list_value[cache[1].v] = self:getVariable(cache[3])
    end
    self.parts = save
    table.insert(self.parts, self:getValueObject("list", list_value))
end

function Interpreter.extractListCall(self)
    local value = self.rest:match("^[A-Za-z_][A-Za-z0-9_]*")
    local variable_type = ""
    if value:match("^v_.+") then
        variable_type = "user_variable"
    elseif value:match("^t_.+") then
        variable_type = "temporary_variable"
    elseif value:match("^a_.+") then
        variable_type = "argument_list"
    elseif value:match("^k_.+") then
        variable_type = "key_variable"
    end
    self:increaseIndex(value)
    self:calculateRest()
    local keys = {}
    local char = self.rest:sub(1, 1)
    while char == "[" do
        self:increaseIndex("", 1)
        local key = self.rest:match("^%[([A-Za-z_][A-Za-z0-9_]*)")
        table.insert(keys, key)
        self:increaseIndex(key)
        self:increaseIndex("", 1)
        self:calculateRest()
        char = self.rest:sub(1, 1)
    end
    table.insert(self.parts, self:getValueObject(variable_type, value, keys))
end

function Interpreter.extractString(self)
    self:increaseIndex("", 1)
    self:calculateRest()
    local str = ""
    local index = 1
    while index <= #self.rest do
        local char = self.rest:sub(index, index)
        if char == "\\" then
            str = str .. char .. self.rest:sub(index + 1, index + 1)
            index = index + 1
        else
            if char == "'" then
                break
            else
                str = str .. char
            end
        end
        index = index + 1
    end
    self:increaseIndex("", index)
    table.insert(self.parts, self:getValueObject("string", str))
end

----------[ DECONSTRUCTION FUNCTIONS ]----------
function Interpreter.deconstruct(self, stop)
    while self.index <= self.length do
        self:calculateRest()
        if self:nextIsListCall() then
            self:extractListCall()
        elseif self:nextIsIdentifier() then
            self:extractIdentifier()
        elseif self:nextIsNumber() then
            self:extractNumber()
        elseif self:nextIsOperator() then
            self:extractOperator()
        elseif self:nextIsString() then
            self:extractString()
        elseif self:nextIsListConstruction() then
            self:extractListConstruction()
        else
            local char = self.rest:sub(1, 1)
            self:increaseIndex("", 1)
            if char ~= " " then
                if char == stop then
                    return
                end
                table.insert(self.parts, self:getValueObject("err", char))
            end
        end
    end
end

function Interpreter.split(self)
    for i = 1, #self.parts, 1 do
        if self.parts[i].vt == "operator" then
            table.insert(self.operators, self.parts[i])
        else
            table.insert(self.values, self.parts[i])
        end
    end
end

function Interpreter.setVariable(self, destination, value)
    if destination.vt == "user_variable" then
        if not (self.envs[#self.envs].mode == "outside") then
            local env = self.scopes[#self.scopes]
            for i = #env, 1, -1 do
                for k, v in pairs(env[i]) do
                    if k == destination.v then
                        --print("OVERRIDING EXISTING USER VARIABLE")
                        local key_index = 1
                        local base = env[i][destination.v]
                        while key_index <= #destination.keys do
                            if base.vt == "list" then
                                local key = self:getVariable(self:getValueObject("key_variable", destination.keys[key_index]))
                                if key_index == #destination.keys then
                                    base.v[key.v] = self:getVariable(value)
                                    return
                                else
                                    base = base.v[key.v]
                                end
                                key_index = key_index + 1
                            else
                                print("ERROR: TRYING TO INDEX NON LIST ITEM")
                                break
                            end
                        end
                        local result = self:getVariable(value)
                        env[i][destination.v] = self:getValueObject(result.vt, result.v, result.keys)
                        return
                    end
                end
            end
            local result = self:getVariable(value)
            for k, v in pairs(self.global_variables) do
                if k == destination.v then
                    if #destination.keys > 0 then
                        local key_index = 1
                        local base = self.global_variables[destination.v]
                        while key_index <= #destination.keys do
                            if base.vt == "list" then
                                local key = self:getVariable(self:getValueObject("key_variable", destination.keys[key_index]))
                                if key_index == #destination.keys then
                                    base.v[key.v] = self:getValueObject(result.vt, result.v, result.keys)
                                    return
                                else
                                    base = base.v[key.v]
                                end
                                key_index = key_index + 1
                            else
                                print("ERROR: TRYING TO INDEX NON LIST VARIABLE")
                                break
                            end
                        end
                    end
                    self.global_variables[destination.v] = self:getValueObject(result.vt, result.v, result.keys)
                    return
                end
            end
            --print("SETTING USER VARIABLE: ", destination.v, value.v, result.v)
            self.scopes[#self.scopes][#self.scopes[#self.scopes]][destination.v] = self:getValueObject(result.vt, result.v, result.keys)
        else
            --print("SETTING / OVERRIDING GLOBAL VARIABLE")
            local result = self:getVariable(value)
            for k, v in pairs(self.global_variables) do
                if k == destination.v then
                    if #destination.keys > 0 then
                        local key_index = 1
                        local base = self.global_variables[destination.v]
                        while key_index <= #destination.keys do
                            if base.vt == "list" then
                                local key = self:getVariable(self:getValueObject("key_variable", destination.keys[key_index]))
                                if key_index == #destination.keys then
                                    base.v[key.v] = self:getValueObject(result.vt, result.v, result.keys)
                                    return
                                else
                                    base = base.v[key.v]
                                end
                                key_index = key_index + 1
                            else
                                print("ERROR: TRYING TO INDEX NON LIST VARIABLE")
                                break
                            end
                        end
                    end
                    self.global_variables[destination.v] = self:getValueObject(result.vt, result.v, result.keys)
                    return
                end
            end
            --print("SETTING GLOBAL VARIABLE FOR THE FIRST TIME")
            self.global_variables[destination.v] = self:getValueObject(result.vt, result.v, result.keys)
        end
            
    elseif destination.vt == "temporary_variable" then
        local result = self:getVariable(value)
        --print("", "RESULT: ", result.vt, result.v)
        self.temp_variables[destination.v] = self:getValueObject(result.vt, result.v, result.keys)
    elseif destination.vt == "argument_list" then
        local result = self:getVariable(value)
        self.arg_lists[destination.v] = self:getValueObject(result.vt, result.v, result.keys)
    elseif destination.vt == "key_variable" then
        local result = self:getVariable(value)
        self.keys[destination.v] = self:getValueObject(result.vt, result.v, result.keys)
    end
end

function Interpreter.getVariable(self, source)
    if source.vt == "user_variable" then
        if not (self.envs[#self.envs].mode == "outside") then
            local env = self.scopes[#self.scopes]
            for i = #env, 1, -1 do
                for k, v in pairs(env[i]) do
                    if k == source.v then
                        --print("GETTING EXISTING USER VARIABLE")
                        local key_index = 1
                        local base = env[i][source.v]
                        while key_index <= #source.keys do
                            if base.vt == "list" then
                                local key = self:getVariable(self:getValueObject("key_variable", source.keys[key_index]))
                                base = base.v[key.v]
                                key_index = key_index + 1
                            else
                                print("ERROR: TRYING TO INDEX NON LIST ITEM")
                                break
                            end
                        end
                        if base then
                            return self:getValueObject(base.vt, base.v, base.keys)
                        else
                            return self:getValueObject("none", "none")
                        end
                    end
                end
            end
        end
        for k, v in pairs(self.global_variables) do
            if k == source.v then
                --print("GETTING EXISTING GLOBAL VARIABLE")
                
                local key_index = 1
                local base = self.global_variables[source.v]
                while key_index <= #source.keys do
                    if base.vt == "list" then
                        local key = self:getVariable(self:getValueObject("key_variable", source.keys[key_index]))
                        base = base.v[key.v]
                        key_index = key_index + 1
                    else
                        print("ERROR: TRYING TO INDEX NON LIST ITEM")
                        break
                    end
                end
                        
                return self:getValueObject(base.vt, base.v, base.keys)
            end
        end
        --print("GETTING:", source.vt, source.v)
        print("ERROR: VARIABLE NOT FOUND ( " .. source.v .. " )")
        return self:getValueObject("none", "none")
    elseif source.vt == "temporary_variable" then
        return self.temp_variables[source.v]
    elseif source.vt == "argument_list" then
        return self.arg_lists[source.v]
    elseif source.vt == "key_variable" then
        return self.keys[source.v]
    end
    return source
end

----------[ EXECUTION FUNCTIONS ]----------
function Interpreter.executeInstruction(self, operator, value1, value2)
    --print("", value1.vt, value1.v, operator.v, value2.vt, value2.v)
    if operator.v == "=" then
        --print("CHECK", value1.v, value2.v)
        self:setVariable(value1, value2)
    elseif operator.v:match("^[%^%+%-%*%/%%]=") then
        if value1.vt:match("^.+_variable$") then
            local result = self:executeInstruction(self:getValueObject("operator", operator.v:sub(1, 1)), value1, value2)
            self:setVariable(value1, result)
        else
            print("ERROR: OPERATOR MUST BE USED TO ASSIGN VALUES ( " .. operator.v .. " )")
            self.fatal_error = true
            return self:getValueObject("none", "none")
        end
    else
        value1 = self:getVariable(value1)
        value2 = self:getVariable(value2)
        local t1 = value1.vt
        local t2 = value2.vt
        local v1 = value1.v
        local v2 = value2.v
        local rt = "none"
        local rv = "none"
        if t1 == "number" then
            if t2 == "number" then
                if operator.v == "+" then
                    rt = "number"
                    rv = v1 + v2
                elseif operator.v == "-" then
                    rt = "number"
                    rv = v1 - v2
                elseif operator.v == "%" then
                    if v2 ~= 0 then
                        rt = "number"
                        rv = v1 % v2
                    end
                elseif operator.v == "*" then
                    rt = "number"
                    rv = v1 * v2
                elseif operator.v == "/" then
                    if v2 ~= 0 then
                        rt = "number"
                        rv = v1 / v2
                    end
                elseif operator.v == "^" then
                    rt = "number"
                    rv = v1 ^ v2
                elseif operator.v == ">" then
                    rt = "boolean"
                    rv = v1 > v2
                elseif operator.v == "<" then
                    rt = "boolean"
                    rv = v1 < v2
                elseif operator.v == ">=" then
                    rt = "boolean"
                    rv = v1 >= v2
                elseif operator.v == "<=" then
                    rt = "boolean"
                    rv = v1 <= v2
                elseif operator.v == "==" then
                    rt = "boolean"
                    rv = v1 == v2
                elseif operator.v == "<<" then
                    rt = "number"
                    rv = bit.lshift(v1, v2)
                elseif operator.v == ">>" then
                    rt = "number"
                    rv = bit.rshift(v1, v2)
                elseif operator.v == "|" then
                    rt = "number"
                    rv = bit.bor(v1, v2)
                elseif operator.v == "&" then
                    rt = "number"
                    rv = bit.band(v1, v2)
                end
            end
        elseif t1 == "boolean" and t2 == "boolean" then
            rt = "boolean"
            if operator.v == "==" then
                rv = v1 == v2
            elseif operator.v == "!=" then
                rv = v1 ~= v2
            elseif operator.v == "&&" then
                rv = v1 and v2
            elseif operator.v == "||" then
                rv = v1 or v2
            end
        elseif t1 == "string" then
            if operator.v == "+" then
                rt = "string"
                rv = v1 .. tostring(v2)
            elseif operator.v == "==" then
                rt = "boolean"
                rv = false
                if v1 == v2 then
                    rv = true
                end 
            elseif operator.v == "~=" then
                rt = "boolean"
                rv = false
                if v1 ~= v2 then
                    rv = true
                end 
            end
        elseif t1 == "list" then
            if t2 == "list" then
                if operator.v == "++" then
                    rt = "list"
                    rv = {}
                    for i = 1, #v1, 1 do
                        table.insert(rv, self:getValueObject(v1[i].vt, v1[i].v))
                    end
                    for i = 1, #v2, 1 do
                        table.insert(rv, self:getValueObject(v2[i].vt, v2[i].v))
                    end
                elseif operator.v == "<-" then
                    table.insert(v1, self:getValueObject(t2, v2))
                    return value1
                else
                    rt = "list"
                    rv = {}
                    for i = 1, math.min(#v1, #v2), 1 do
                        table.insert(rv, self:executeInstruction(operator, v1[i], v2[i]))
                    end
                end
            else
                if operator.v == "<-" then
                    table.insert(v1, self:getValueObject(t2, v2))
                    return value1
                end
            end
        elseif t1 == "none" then
            if operator.v == "==" then
                if t2 == "none" then
                    rt = "boolean"
                    rv = true
                else
                    rt = "boolean"
                    rv = false
                end
            end
        end
        return self:getValueObject(rt, rv)
    end
end

function Interpreter.printUserVariable(self, name)
    local val = self:getVariable(self:getValueObject("user_variable", name))
    print(name .. ":", val.vt, val.v)
    if val.vt == "list" then
        print("LENGTH: ", #val.v)
        for k, v in pairs(val.v) do
            print("   |=> ", k, v.v)
        end
    end
end

function Interpreter.evaluateNextLine(self)
    self.operators = {}
    self.values = {}
    local entry = self.envs[#self.envs]
    entry.index = entry.index + 1
    if entry.mode == "outside" then
        if self.outside[entry.index] then
            self:structure(self.outside[entry.index])
        else
            return true
        end
    else
        if self.code[entry.index] then
            self:structure(self.code[entry.index])
        else
            table.remove(self.envs, #self.envs)
        end
    end
    return self.fatal_error
end

function Interpreter.structure(self, line)
    --print("", "LINE:", line)
    self.current_code_line = tonumber(line:match("^(%d+)|%s+.*"))
    line = line:gsub("^%d+| ", "")
    if line:match("^push function env$") then
        --table.insert(self.scopes[#self.scopes], {}) 
    elseif line:match("^pop function env$") then
        self:removeFunctionFromStack()
    elseif line:match("^function_call.+") then
        self:callFunction(line)
    elseif line:match("^if.+") then
        self:evaluateIf(line)
    elseif line:match("^return") then
        self:removeFunctionFromStack()
    elseif line:match("^push if env$") then
        self:addScope()
    elseif line:match("^pop if env$") then
        self:removeScope()
    elseif line:match("^push loop env$") then
        self:addScope()
    elseif line:match("^pop loop env$") then
        self:removeScope()
    elseif line:match("jumpr%s+-?%d+") then
        self:relativeJump(line)
    elseif line:match("^push else env$") then
        self:addScope()
    elseif line:match("^pop else env$") then
        self:removeScope()
    else
        self:evaluate(line)
    end
end

function Interpreter.removeFunctionFromStack(self)
    table.remove(self.scopes, #self.scopes)
    table.remove(self.envs, #self.envs)
end

function Interpreter.addScope(self)
    table.insert(self.scopes[#self.scopes], {})
end

function Interpreter.relativeJump(self, line)
    self.envs[#self.envs].index = self.envs[#self.envs].index + tonumber((line:match("jumpr%s+(.+)$"))) - 1
end

function Interpreter.removeScope(self)
    table.remove(self.scopes[#self.scopes], #self.scopes[#self.scopes])
end

function Interpreter.evaluateIf(self, line)
    local condition_name = line:match("^if%s+(.+)%s+>>.+$")
    local jump_line = line:match("^if%s+.+%s+>>(.+)$")
    local value = self:getVariable(self:getValueObject("temporary_variable", condition_name))
    if value.vt == "boolean" then
        if not value.v then
            self.envs[#self.envs].index = tonumber(jump_line - 1)
        end
    else
        print("ERROR: CONDITION NEEDS TO BE BOOLEAN")
        self.envs[#self.envs].index = tonumber(jump_line - 1)
    end
end

function Interpreter.callFunction(self, line)
    self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("none", "none"))
    local name = line:match("^function_call%s+([A-Za-z_][A-Za-z0-9_]*).+")
    local arg_list = line:match("^function_call%s+[A-Za-z_][A-Za-z0-9_]*%s+([A-Za-z_][A-Za-z0-9_]*)")
    for i = 1, #self.system_functions, 1 do
        if name == self.system_functions[i] then
            local values = self:getVariable(self:getValueObject("argument_list", arg_list))
            self:executeSystemFunction(self.system_functions[i], values)
            return
        end
    end
    for i = 1, #self.signatures, 1 do
        if self.signatures[i].name == name then
            local signature = self.signatures[i]
            local variables = {}
            local values = self:getVariable(self:getValueObject("argument_list", arg_list))
            for p = 1, #signature.parameters, 1 do
                --print("PARAMETER: ", signature.parameters[p])
                if values.v[p] then
                    variables[signature.parameters[p]] = self:getValueObject(values.v[p].vt, values.v[p].v, values.v[p].keys)
                else
                    variables[signature.parameters[p]] = self:getValueObject("none", "none")
                end
            end
            table.insert(self.scopes, {variables})
            table.insert(self.envs, {mode = "function", index = signature.line - 1})
            return
        end
    end
    print("ERROR: FUNCTION NOT FOUND!")
end

function Interpreter.getVectorListObject(self, vec)
    return self:getValueObject("list", {self:getValueObject("number", vec.x), self:getValueObject("number", vec.y), self:getValueObject("number", vec.z)})
end

function Interpreter.executeSystemFunction(self, name, values)
    --print("NAME: ", name, #values.v)
    self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("none", "none"))
    if name == "print" then
        print("[HLL]: ", self:getDeepString(values))
    elseif name == "vec" then
        local components = {}
        for i = 1, #values.v, 1 do
            if values.v[i].vt == "number" then
                table.insert(components, self:getValueObject("number", values.v[i].v))
            else
                return
            end
        end
        self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("list", components))
    elseif #values.v == 0 then
        --[[ PUT THE VECTOR HERE ]]
        if name == "pos" then
            self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getVectorListObject({x=1, y=2, z=3}))
        elseif name == "dir" then
            self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getVectorListObject({x=1, y=0, z=0}))
        elseif name == "vel" then
            self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getVectorListObject({x=1, y=1, z=1}))
        elseif name == "random" then
            self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", math.random()))
        elseif name == "time" then
            self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", os.time()))
        elseif name == "input" then
            self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("string", io.read()))
        end
    elseif #values.v == 1 then
        if name == "type" then
            self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("string", values.v[1].vt))
        elseif name == "exists" and values.v[1].vt == "string" then
            for i = 1, #self.files, 1 do
                if self.files[i].header.filename == values.v[1].v then
                    self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("boolean", true)) 
                    return
                end
            end
            self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("boolean", false))
            return
        elseif name == "char" and values.v[1].vt == "number" then
            if values.v[1].v >= 0 then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("string", string.char(values.v[1].v)))
            else
                print("ERROR: INVALID VALUE TO CONVERT TO CHAR (VALUE >= 0)")
            end
        elseif name == "remove" and values.v[1].vt == "string" then
            for i = 1, #self.files, 1 do
                if self.files[i].header.filename == values.v[1].v then
                    table.remove(self.files, i)
                    self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("boolean", true)) 
                    return
                end
            end
            self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("boolean", false))
            return
        elseif name == "stream" and values.v[1].vt == "string" then
            for i = 1, #self.files, 1 do
                if self.files[i].header.filename == values.v[1].v then
                    self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("stream", {filename = self.files[i].header.filename, filetype = self.files[i].header.filetype, ref=self.files[i]})) 
                    return
                end
            end
            print("ERROR: CANT OPEN STREAM TO NONE EXISTING FILE")
        elseif name == "clear" and values.v[1].vt == "stream" then
            values.v[1].v.ref.content = {}
        elseif name == "open" then
            if values.v[1].vt == "string" then
                for i = 1, #self.files, 1 do
                    if self.files[i].header.filename == values.v[1].v then
                        self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("fileiterator", {index=1, filename=self.files[i].header.filename, filetype=self.files[i].header.filetype, ref=self.files[i]}))
                        return
                    end
                end
                print("ERROR: FILE NOT FOUND")
            else
                print("ERROR: FILENAME MUST BE STRING")
            end
        elseif name == "next" and values.v[1].vt == "fileiterator" then
            if values.v[1].v.ref.content[values.v[1].v.index] then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("string", values.v[1].v.ref.content[values.v[1].v.index]))
                values.v[1].v.index = values.v[1].v.index + 1
            else
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("none", "none"))
            end
        elseif name == "current" and values.v[1].vt == "fileiterator" then
            self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", values.v[1].v.index))
        elseif name == "filetype" then
            if values.v[1].vt == "fileiterator" or values.v[1].vt == "stream" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("string", values.v[1].v.filetype))
            end
        elseif name == "filename" then
            if values.v[1].vt == "fileiterator" or values.v[1].vt == "stream" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("string", values.v[1].v.filename))
            end
        elseif name == "normalize" and values.v[1].vt == "list" then
            local sum = 0
            for i = 1, #values.v[1].v, 1 do
                if values.v[1].v[i].vt == "number" then
                    sum = sum + math.pow(values.v[1].v[i].v, 2)
                else
                    print("ERROR: TRYING TO NORMALIZE VECTOR WITH NON NUMERIC VALUES")
                    return
                end
            end
            local fraction = math.sqrt(sum)
            local scaled = {}
            for i = 1, #values.v[1].v, 1 do
                table.insert(scaled, self:getValueObject("number", values.v[1].v[i].v / fraction))
            end
            self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("list", scaled))
        elseif name == "length" and values.v[1].vt == "list" then
            local sum = 0
            for i = 1, #values.v[1].v, 1 do
                if values.v[1].vt == "number" then
                    sum = sum + math.pow(values.v[1].v, 2)
                else
                    print("ERROR: TRYING TO GET LENGTH OF A NON VECTOR FORMAT LIST")
                    return
                end
            end
            self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", math.sqrt(sum)))
        elseif name == "str" then
            if values.v[1].vt == "list" then
                local str = ""
                for i = 1, #values.v[1].v, 1 do
                    if values.v[1].v[i].vt == "number" then
                        if values.v[1].v[i].v >= 0 then
                            str = str .. string.char(values.v[1].v[i].v)
                        else
                            print("ERROR: INVALID VALUE TO CONVERT TO CHAR (VALUE >= 0)")
                            return
                        end
                    else
                        print("ERROR: TRYING TO CONSTRUCT A STRING FROM LIST WITH NON NUMERIC VALUES")
                        return
                    end
                end
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("string", str))
            elseif values.v[1].vt == "number" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("string", tostring(values.v[1].v)))
            end
        elseif name == "num" and values.v[1].vt == "string" then
            if values.v[1].v:match("^%d+.?%d*$") then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", tonumber(values.v[1].v)))
            end
        elseif name == "size" then
            if values.v[1].vt == "list" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", #values.v[1].v))
            elseif values.v[1].vt == "fileiterator" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", #values.v[1].v.ref.content))
            elseif values.v[1].vt == "string" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", #values.v[1].v))
            end
        elseif values.v[1].vt == "number" then
            if name == "abs" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", math.abs(values.v[1].v)))
            elseif name == "seed" then
                math.randomseed(values.v[1].v)
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("none", "none"))
            elseif name == "deg" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", math.deg(values.v[1].v)))
            elseif name == "rad" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", math.rad(values.v[1].v)))
            elseif name == "cos" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", math.cos(values.v[1].v)))
            elseif name == "sin" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", math.sin(values.v[1].v)))
            elseif name == "tan" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", math.tan(values.v[1].v)))
            elseif name == "acos" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", math.acos(values.v[1].v)))
            elseif name == "asin" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", math.asin(values.v[1].v)))
            elseif name == "atan" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", math.atan(values.v[1].v)))
            elseif name == "ceil" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", math.ceil(values.v[1].v)))
            elseif name == "floor" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", math.floor(values.v[1].v)))
            elseif name == "exp" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", math.exp(values.v[1].v)))
            end
        elseif name == "keys" then
            if values.v[1].vt == "list" then
                local combined = {}
                for k, v in pairs(values.v[1].v) do
                    table.insert(combined, self:getValueObject("string", tostring(k)))
                end
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("list", combined))
            end
        elseif name == "values" then
            if values.v[1].vt == "list" then
                local combined = {}
                for k, v in pairs(values.v[1].v) do
                    table.insert(combined, self:getValueObject(v.vt, v.v, v.keys))
                end
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("list", combined))
            end
        end
    elseif #values.v == 2 then
        if name == "combine" then
            if values.v[1].vt == "list" and values.v[1].vt == "list" then
                local combined = {}
                for i = 1, #values.v[1].v, 1 do
                    table.insert(combined, self:getValueObject(values.v[1].v[i].vt, values.v[1].v[i].v, values.v[1].v[i].keys))
                end
                for i = 1, #values.v[2].v, 1 do
                    table.insert(combined, self:getValueObject(values.v[2].v[i].vt, values.v[2].v[i].v, values.v[2].v[i].keys))
                end
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("list", combined))
            end
        elseif name == "matches" and values.v[1].vt == "string" and values.v[2].vt == "string" then
            if pcall(function(data, pattern) data:match(pattern) end, values.v[1].v, values.v[2].v) then
                if values.v[1].v:match(values.v[2].v) then
                    self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("boolean", true))
                else
                    self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("boolean", false))
                end
            else
                print("ERROR: INVALID PATTERN ( " .. values.v[2].v .. " )")
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("boolean", false))
            end
        elseif name == "line" and values.v[1].vt == "fileiterator" and values.v[2].vt == "number" then
            if values.v[1].v.ref.content[values.v[2].v] then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("string", values.v[1].v.ref.content[values.v[2].v]))
            else
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("none", "none"))
            end
        elseif name == "new" and values.v[1].vt == "string" and values.v[2].vt == "string" then
            for i = 1, #self.files, 1 do
                if self.files[i].header.filename == values.v[1].v then
                    self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("boolean", false))
                    return
                end
            end
            table.insert(self.files, {header = {filename = values.v[1].v, filetype = values.v[2].v}, content = {}})
            self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("boolean", true))
        elseif name == "remove" and values.v[1].vt == "stream" and values.v[2].vt == "number" then
            local removed = table.remove(values.v[1].v.ref.content, values.v[2].v)
            if removed then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("string", removed))
            else
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("none", "none"))
            end
        elseif name == "write" and values.v[1].vt == "stream" and values.v[2].vt == "string" then
            table.insert(values.v[1].v.ref.content, values.v[2].v)
        elseif name == "in" then
            if values.v[2].vt == "string" then
                
            end
        elseif name == "out" then
            if values.v[2].vt == "string" then
                
            end
        elseif name == "min" then
            if values.v[1].vt == "number" and values.v[2].vt == "number" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", math.min(values.v[1].v, values.v[2].v)))
            end
        elseif name == "max" then
            if values.v[1].vt == "number" and values.v[2].vt == "number" then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", math.max(values.v[1].v, values.v[2].v)))
            end
        else
            if name == "scale" then
                if values.v[1].vt == "list" and values.v[2].vt == "number" then
                    local scaled = {}
                    for i = 1, #values.v[1].v, 1 do
                        if values.v[1].v[i].vt == "number" then
                            table.insert(scaled, self:getValueObject("number", values.v[1].v[i].v * values.v[2].v))
                        else
                            print("ERROR: TRYING TO SCALE VECTOR WITH NON NUMERIC VALUES")
                            return
                        end
                    end
                    self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("list", scaled))
                end
            else
                if values.v[1].vt == "list" and values.v[2].vt == "list" then
                    if #values.v[1].v == #values.v[2].v then
                        local calculated = {}
                        if name == "add" then
                            for i = 1, #values.v[1].v, 1 do
                                if values.v[1].v[i].vt == "number" then
                                    table.insert(calculated, self:getValueObject("number", values.v[1].v[i].v + values.v[2].v[i].v))
                                else
                                    print("ERROR: TRYING TO SCALE VECTOR WITH NON NUMERIC VALUES")
                                    return
                                end
                            end
                        elseif name == "sub" then
                            for i = 1, #values.v[1].v, 1 do
                                if values.v[1].v[i].vt == "number" then
                                    table.insert(calculated, self:getValueObject("number", values.v[1].v[i].v - values.v[2].v[i].v))
                                else
                                    print("ERROR: TRYING TO SCALE VECTOR WITH NON NUMERIC VALUES")
                                    return
                                end
                            end
                        elseif name == "dot" then
                            local sum = 0
                            for i = 1, #values.v[1].v, 1 do
                                if values.v[1].v[i].vt == "number" then
                                    sum = sum + values.v[1].v[i].v * values.v[2].v[i].v
                                else
                                    print("ERROR: TRYING TO SCALE VECTOR WITH NON NUMERIC VALUES")
                                    return
                                end
                            end
                            self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", sum))
                            return
                        elseif name == "cross" then
                            if #values.v[1].v == 3 then
                                for i = 1, #values.v[1].v, 1 do
                                    if not values.v[1].v[i].vt == "number" then
                                        print("ERROR: TRYING TO SCALE VECTOR WITH NON NUMERIC VALUES")
                                        return
                                    end
                                end
                                local v1 = values.v[1]
                                local v2 = values.v[2]
                                local x = v1.v[2].v * v2.v[3].v - v2.v[2].v * v1.v[3].v
                                local y = v1.v[3].v * v2.v[1].v - v2.v[3].v * v1.v[1].v
                                local z = v1.v[1].v * v2.v[2].v - v2.v[1].v * v1.v[2].v
                                calculated = {self:getValueObject("number", x), self:getValueObject("number", y), self:getValueObject("number", z)}
                            else
                                print("ERROR: VECTOR NEEDS 3 DIMENSIONS")
                            end
                        elseif name == "angle" then
                            local sum = 0
                            local l1 = 0
                            local l2 = 0
                            for i = 1, #values.v[1].v, 1 do
                                if values.v[1].v[i].vt == "number" then
                                    sum = sum + values.v[1].v[i].v * values.v[2].v[i].v
                                    l1 = l1 + math.pow(values.v[1].v[i].v, 2)
                                    l2 = l2 + math.pow(values.v[2].v[i].v, 2)
                                else
                                    print("ERROR: TRYING TO SCALE VECTOR WITH NON NUMERIC VALUES")
                                    return
                                end
                            end
                            self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("number", math.acos(sum / (math.sqrt(l1) * math.sqrt(l2)))))
                            return
                        end
                        self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("list", calculated))
                    else
                        print("ERROR: VECTORS DIFFER IN LENGTH")
                    end
                else
                    print("ERROR: TRYING TO ADD NONE LIST VALUES")
                end
            end
        end
    elseif #values.v == 3 then
        if name == "insert" and values.v[1].vt == "stream" and values.v[2].vt == "number" and values.v[3].vt == "string" then
            table.insert(values.v[1].v.ref.content, values.v[2].v, values.v[3].v)
        elseif name == "substring" and values.v[1].vt == "string" and values.v[2].vt == "number" and values.v[3].vt == "number" then
            self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("string", values.v[1].v:sub(values.v[2].v, values.v[3].v)))
        elseif name == "replace" and values.v[1].vt == "string" and values.v[2].vt == "string" and values.v[3].vt == "string" then
            if pcall(function(data, pattern, replacement) data:gsub(pattern, replacement) end, values.v[1].v, values.v[2].v, values.v[3].v) then
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("string", values.v[1].v:gsub(values.v[2].v, values.v[3].v)))
            else
                print("ERROR: INVALID PATTERN ( " .. values.v[2].v .. " )")
                self:setVariable(self:getValueObject("temporary_variable", "t_return"), self:getValueObject("none", "none"))
            end
        end
    end
end

function Interpreter.getDeepString(self, obj)
    local str = ""
    if obj.vt == "list" then
        str = "["
        for k, v in pairs(obj.v) do
            str = str .. k .. ": " .. self:getDeepString(v) .. ", "
        end
        str = ((str:match("(%[.+), ")) or "[") .. "]"
    elseif obj.vt == "fileiterator" then
        str = "[fileiterator: " .. obj.v.filename .. "]"
    elseif obj.vt == "stream" then
        str = "[stream: " .. obj.v.filename .. "]"
    else
        str = tostring(obj.v)
    end
    return str
end

function Interpreter.evaluate(self, line)
    self.expression = line
    self.index = 1
    self.length = #line
    self.parts = {}
    self:deconstruct()
    self:split()
    
    for i = 1, #self.ooe, 1 do
        local found = false
        repeat
            found = false
            for k = 1, #self.operators, 1 do
                if self.operators[k].v == self.ooe[i] then
                    local r = table.remove(self.operators, k)
                    local v1 = table.remove(self.values, k)
                    local v2 = table.remove(self.values, k)
                    local result = self:executeInstruction(r, v1, v2)
                    if result then
                        table.insert(self.values, k, result)
                    end
                    found = true
                    break
                end
            end
        until not found
    end
    
    --print("-----[ PARTS ]------")
    --for i = 1, #self.parts, 1 do
        --print(self.parts[i].vt, self.parts[i].v)
    --end
end

function Interpreter.printVariables(self)
    print("-----[ RESULTS ]-----")
    print("-----[ USER VARIABLES ]-----")
    for i = 1, #self.scopes, 1 do
        for a = 1, #self.scopes[i], 1 do
            for k, v in pairs(self.scopes[i][a]) do
                self:printUserVariable(k)
            end
        end
    end
    print("-----[ GLOBAL VARIABLES ]-----")
    for k, v in pairs(self.global_variables) do
        print(k, self:getVariable(self:getVariable(v)).v)
        if type(self:getVariable(self:getVariable(v)).v) == "table" then
            for k, v in pairs(self:getVariable(self:getVariable(v)).v) do
                print(" |=> ", k, v.vt, v.v)
            end
        end
    end
end