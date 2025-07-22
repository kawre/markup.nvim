local function use(spec)
	local fiber = Markup.reconciler.static.get_currently_rendering_fiber(true)
	return fiber.memoized_props.value
end

return use
