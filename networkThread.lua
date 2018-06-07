local socket = require("socket")

local channel, port = ...

local server = assert(socket.bind("*", port))
print("Host", server:getsockname())

local client, err = server:accept()
print("client", client)
if not client then
    print("Error accepting connection:", err)
    return
end

while true do
    local data, err = client:receive(256)
    if err then
        if err == "closed" then
            print("Connection closed.")
            break
        else
            print("Error receiving data:", err)
        end
    end
    channel:push(data)
end
client:close()
