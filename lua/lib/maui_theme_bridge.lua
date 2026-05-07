--- Minimal Maui theme bridge when Maui is not installed or lib was omitted from the package.
--- Matches the stub used in buttonmaster: no-op push/pop so ImGui uses default or local styling.
return {
    push = function() return nil end,
    pop = function() end,
}
