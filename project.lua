return {
	DEBUG_MODE = true,

	title = "Flynight",
	file = "FNF-LOVE.FLYNIGHT",
	icon = "art/icon.png",

	version = "0.7.1",
	FNversion = "0.0.1 WIP",

	package = "dev.flynight",
	width = 1280,
	height = 720,
	FPS = 60,
	company = "Kaoy",

	flags = {
		loxelInitialAutoPause = true,
		loxelInitialParallelUpdate = true,
		loxelInitialAsyncInput = false,

		loxelForceRenderCameraComplex = false,
		loxelDisableRenderCameraComplex = false,
		loxelDisableScissorOnRenderCameraSimple = false,
		loxelDefaultClipCamera = true
	}
}
