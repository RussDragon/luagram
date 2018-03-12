-- require 'lua-nucleo'

local https = require'ssl.https'
local encode = require'multipart-post'.encode
local json = require'cjson'
local utf8 = require'lua-utf8'

local type, table_concat, table_insert, pairs, tostring, setmetatable =
			type, table.concat, table.insert, pairs, tostring, setmetatable

-------------------------------------------------------------------------------

local preparePOST = function(t)
	if type(t) == 'number' then return tostring(t) end
	if type(t) == 'string' then return t end
	if not t then return end

  local res = {}
  for k, v in pairs(t) do
  	res[k] = tostring(v) or v
  end

  return res
end

local split_string_by_bound = function(str, size)
	local results = {}
	local curString, pos = str, 1

	while utf8.len(curString) > 0 do 
		if utf8.len(curString) > size then
			local subString = utf8.sub(curString, 1, size)
			pos = utf8.find(subString, '(%s)%S*$')

			if not pos then pos = size end
		else pos = utf8.len(curString) end

		results[#results+1] = utf8.sub(curString, 1, pos)
		pos = pos + 1
		curString = utf8.sub(curString, pos, utf8.len(curString))
	end

	return results
end

local saveLog = function(text)
	print(text)
end

-------------------------------------------------------------------------------

local api = {}

api.__index = api

function api:new(api_address, api_token)
	if not api_token or not api_address then error('API token and Telegram API URL should be specified.') return nil end

	api_token = api_token:gsub('%s+', '')
	api_address = api_address:gsub('%s+', '')
	if not api_address:match('/$') then api_address = api_address .. '/' end

	local obj = {}

	obj.config = {}
	obj.config.last_update_id = 0
	obj.config.api_token = api_token
	obj.config.api_address = api_address
	obj.config.call_address = api_address .. api_token .. '/'

	setmetatable(obj, self)
	return obj
end

function api:request(method, data, log)
	-- assertions here
	data = preparePOST(data)

	local response = {}
	local body, boundary = encode(data)

	local req_data = {
		url = self.config.call_address .. method,
		method = 'POST',
		headers = {
			['content-length'] = #body,
			['content-type'] = 'multipart/form-data; boundary=' .. boundary
		},
		source = ltn12.source.string(body),
		sink = ltn12.sink.table(response)
	}

	local succ, code, headers, status = https.request(req_data)

	if not succ or not status then error(code) end

	return {
		success = succ,
		code = code,
		headers = headers,
		status = status,
		response = json.decode(response[1])
	}
end

function api:getUpdates(args)
	local body = args or {}
	body.offset = args and args.offset or self.config.last_update_id + 1

	local data = self:request('getUpdates', body).response
	if not data or not data.ok then saveLog('Something went wrong with getUpdates call.', 'action_log.txt') return nil end

	local res = data.result
	self.config.last_update_id = res[#res] and res[#res].update_id or self.config.last_update_id

	return res
end

function api:sendMessage(args)
	-- DEFAULTS
	-- args.parse_mode = 'HTML'

	if not args or type(args) ~= 'table' or not args.text or not args.chat_id then 
		saveLog('Method sendMessage needs chat_id and text arguments. Others are optional.') 
		return nil
	end

	if utf8.len(args.text) > 4096 then
		local msgParts = split_string_by_bound(args.text, 4096)
		local responses = {}

		if msgParts then
			for i, v in ipairs(msgParts) do
				args.text = v
				responses[#responses+1] = self:request('sendMessage', args, 'Sending ' .. i .. ' part')
			end

			return results, true
		end
	else
		return self:request('sendMessage', args), nil
	end
end

function api:forwardMessage(args)
end

function api:sendPhoto(args)
	if not args or type(args) ~= 'table' or not args.photo or not args.chat_id then 
		saveLog('Method sendMessage needs chat_id and photo arguments. Others are optional.') 
		return nil
	end

	return self:request('sendPhoto', args)
end

function api:sendChatAction(args)
end

function api:answerCallbackQuery(args)
end

function api:editMessageText(args)
end

function api:deleteMessage(args)
end

function api:getMe()
	local req = self:request('getMe')

	if req.ok then
		saveLog('API is online. Your bot is working and available. API token set up.') 
		saveLog('Bot id: ' .. req.result.id)
		saveLog('Bot name: ' .. req.result.first_name .. (req.result.last_name or ''))
		saveLog('Bot username: ' .. req.result.username )
	end
end

-------------------------------------------------------------------------------

api.inline_keyboard = {}
local ikeyboard = api.inline_keyboard

function ikeyboard:addRow(row)
	row = row or {}

	table_insert(self.keyboard, row)
end

function ikeyboard:addButton(row, args)
	if row > #self.keyboard then 
		error('addButton: row can not be greater than amount of rows in keyboard')
	end

	local button = {}

	for k, v in pairs(args) do
		button[k] = v
	end

	table_insert(self.keyboard[row], button)
end

function ikeyboard:encode()
	local kobj = {}
	kobj[self.type] = self.keyboard

	print(require'serpent'.block(kobj))
	return json.encode(kobj)
end



do
	local addRow = function(self, row)
		row = row or {}

		table_insert(self.keyboard, row)
	end

	local addButton = function(self, row, args)
		if row > #self.keyboard then 
			error('addButton: row can not be greater than amount of rows in keyboard')
		end

		local button = {}

		for k, v in pairs(args) do
			button[k] = v
		end

		table_insert(self.keyboard[row], button)
	end

	local encode = function(self)
		local kobj = {}
		kobj[self.type] = self.keyboard

		print(require'serpent'.block(kobj))
		return json.encode(kobj)
	end

	api.newKeyboard = function(self, type)
		local obj = {
			addRow = addRow,
			addButton = addButton,
			encode = encode
		}
		obj.keyboard = {}
		obj.type = type

		return obj
	end
end

-------------------------------------------------------------------------------

return api
