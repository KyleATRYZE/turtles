-- Makes this computer a screen station (screens.lua) and installs the swarm programs.
--   wget run https://raw.githubusercontent.com/KyleATRYZE/turtles/main/doors/screen.lua
-- Optional: a post name (wall, panel, rack, gate) to skip the guess by monitor size, e.g.
--   wget run https://raw.githubusercontent.com/KyleATRYZE/turtles/main/doors/screen.lua wall
local post = ...
local h = fs.open(".role", "w"); h.write("screen"); h.close()
if post and post ~= "" then h = fs.open(".post", "w"); h.write(post); h.close() end
if not os.getComputerLabel() then os.setComputerLabel("Screen-" .. os.getComputerID()) end
shell.run("wget", "run", "https://raw.githubusercontent.com/KyleATRYZE/turtles/main/install.lua")
