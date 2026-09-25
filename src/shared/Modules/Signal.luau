--!strict
-- Minimal signal class (connections are called in their own threads via task.spawn).

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	DisconnectAll: (self: Signal<T...>) -> (),
}

type Listener = { fn: (...any) -> (), connection: any }

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({ _listeners = {} :: { Listener } }, Signal)
	return self :: any
end

function Signal:Connect(fn: (...any) -> ()): Connection
	local listeners: { Listener } = self._listeners
	local connection = { Connected = true }
	local listener: Listener = { fn = fn, connection = connection }
	function connection.Disconnect(conn: any)
		if not conn.Connected then
			return
		end
		conn.Connected = false
		local index = table.find(listeners, listener)
		if index then
			table.remove(listeners, index)
		end
	end
	table.insert(listeners, listener)
	return connection :: any
end

function Signal:Once(fn: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...: any)
	local listeners: { Listener } = self._listeners
	for _, listener in table.clone(listeners) do
		if listener.connection.Connected then
			task.spawn(listener.fn, ...)
		end
	end
end

function Signal:Wait(): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:DisconnectAll()
	local listeners: { Listener } = self._listeners
	for _, listener in listeners do
		listener.connection.Connected = false
	end
	table.clear(listeners)
end

return Signal
