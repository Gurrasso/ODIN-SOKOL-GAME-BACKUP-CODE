#+feature dynamic-literals
package main


//   imports
import "base:intrinsics"
import "base:runtime"
import "core:log"
import "core:math"
import "core:math/linalg"
// stb images
import stbi "vendor:stb/image"
// sokol imports
import sapp "./sokol/app"
import shelpers "./sokol/helpers"
import sg "./sokol/gfx"

//shortening of linalg.to_radians
to_radians :: linalg.to_radians

//global var for context
default_context: runtime.Context

//define our own types
Mat4 :: matrix[4, 4]f32
Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

// the vertex data
Vertex_Data :: struct{
	pos: Vec3,
	col: sg.Color,
	uv: Vec2,
}

// Handle multiple objects
Object :: struct{
	pos: Vec3,
	rot: Vec3,
	img: sg.Image,
	vertex_buffer: sg.Buffer,
	id: cstring,

}

//global vars
Globals :: struct {
	should_quit: bool,
	shader: sg.Shader,
	pipeline: sg.Pipeline,
	index_buffer: sg.Buffer,
	objects: [dynamic]Object,
	sampler: sg.Sampler,
	rotation: Vec3,
	camera: struct{
		position: Vec3,
		target: Vec3,
		look: Vec2,
	}
}
g: ^Globals

//main
main :: proc(){
	//logger
	context.logger = log.create_console_logger()
	default_context = context


	//sokol app
	sapp.run({
		width = 800,
		height = 600,
		window_title = "ODIN-SOKOL-GAME",

		allocator = sapp.Allocator(shelpers.allocator(&default_context)),
		logger = sapp.Logger(shelpers.logger(&default_context)),

		init_cb = init_cb,
		frame_cb = frame_cb,
		cleanup_cb = cleanup_cb,
		event_cb = event_cb,
	})
}

//initialization
init_cb :: proc "c" (){
	context = default_context

	//setup for the sokol graphics
	sg.setup({
		environment = shelpers.glue_environment(),
		allocator = sg.Allocator(shelpers.allocator(&default_context)),
		logger = sg.Logger(shelpers.logger(&default_context)),
	})

	//lock mouse and hide mouse
	sapp.show_mouse(false)
	sapp.lock_mouse(true)

	//the globals
	g = new(Globals)

	//setup the camera
	g.camera = {
		position = { 0,0,8 },
		target = { 0,0,1 },
	}
	
	//make the shader and pipeline
	g.shader = sg.make_shader(main_shader_desc(sg.query_backend()))
	g.pipeline = sg.make_pipeline({
		shader = g.shader,
		layout = {
			//different attributes
			attrs = {
				ATTR_main_pos = { format = .FLOAT3 },
				ATTR_main_col = { format = .FLOAT4 },
				ATTR_main_uv = { format = .FLOAT2 },
			}
		},

		// specify that we want to use index buffer
		index_type = .UINT16,
		//make it so objects draw based on distance from camera
		depth = {
			write_enabled = true,
			compare = .LESS_EQUAL
		}
	})


	

	// indices
	indices := []u16 {
		0, 1, 2,
		2, 1, 3,
	}
	// index buffer
	g.index_buffer = sg.make_buffer({
		type = .INDEXBUFFER,
		data = sg_range(indices),
	})

	create_sprite("./assets/textures/RETRO_TEXTURE_PACK_SAMPLE/SAMPLE/BRICK_1A.PNG", {0, 0}, {2, 2}, "hello")

	//create the sampler
	g.sampler = sg.make_sampler({})
}

//  proc for loading an image from a file
load_image :: proc(filename: cstring) -> sg.Image{
	w, h: i32
	pixels := stbi.load(filename, &w, &h, nil, 4)
	assert(pixels != nil)

	image := sg.make_image({
		width = w,
		height = h,
		pixel_format = .RGBA8,
		data = {
			subimage = {
				0 = {
					0 = {
						ptr = pixels,
						size = uint(w * h * 4)
					}
				}
			}
		}
	})
	stbi.image_free(pixels)

	return image
}

//cleanup
cleanup_cb :: proc "c" (){
	context = default_context

	//destroy all the things we init
	for obj in g.objects{
		sg.destroy_image(obj.img)
		sg.destroy_buffer(obj.vertex_buffer)
	}
	sg.destroy_sampler(g.sampler)
	sg.destroy_buffer(g.index_buffer)
	sg.destroy_pipeline(g.pipeline)
	sg.destroy_shader(g.shader)

	//free the global vars
	free(g)

	//shut down sokol graphics
	sg.shutdown()
}

//Every frame
frame_cb :: proc "c" (){
	context = default_context

	//tell the program to exit
	if key_down[.ESCAPE] {
		g.should_quit = true
	}

	//exit the program
	if(g.should_quit){
		sapp.quit()
		return
	}

	//deltatime
	dt := f32(sapp.frame_duration())

	// update_camera(dt)

	// g.rotation.x += linalg.to_radians(ROTATION_SPEED * dt)
	// g.rotation.y += linalg.to_radians(ROTATION_SPEED * dt)
	// g.rotation.z += linalg.to_radians(ROTATION_SPEED * dt)

	update_sprite({g.rotation.x, 0}, {0, 0, g.rotation.y}, "hello")

	//  projection matrix(turns normal coords to screen coords)
	p := linalg.matrix4_perspective_f32(70, sapp.widthf() / sapp.heightf(), 0.0001, 1000)
	//view matrix
	v := linalg.matrix4_look_at_f32(g.camera.position, g.camera.target, {0, 1, 0})

	sg.begin_pass({ swapchain = shelpers.glue_swapchain()})

	//apply the pipeline to the sokol graphics
	sg.apply_pipeline(g.pipeline)

	//do things for all objects
	for obj in g.objects {
		//matrix
		m := linalg.matrix4_translate_f32(obj.pos) * linalg.matrix4_from_yaw_pitch_roll_f32(to_radians(obj.rot.y), to_radians(obj.rot.x), to_radians(obj.rot.z))



		//apply the bindings(something that says which things we want to draw)
		b := sg.Bindings {
			vertex_buffers = { 0 = obj.vertex_buffer },
			index_buffer = g.index_buffer,
			images = { IMG_tex = obj.img },
			samplers = { SMP_smp = g.sampler },
		}

		sg.apply_bindings(b)

		//apply uniforms
		sg.apply_uniforms(UB_vs_params, sg_range(&Vs_Params{
			mvp = p * v * m
		}))

		//drawing
		sg.draw(0, 6, 1)
	}

	sg.end_pass()

	sg.commit()

	mouse_move = {}
}

MOVE_SPEED :: 3
LOOK_SENSITIVITY :: 0.3

//function for moving around camera
update_camera :: proc(dt: f32) {
	move_input: Vec2
	if key_down[.W] do move_input.y = 1
	else if key_down[.S] do move_input.y = -1
	if key_down[.A] do move_input.x = -1
	else if key_down[.D] do move_input.x = 1

	look_input: Vec2 = -mouse_move * LOOK_SENSITIVITY
	g.camera.look += look_input
	g.camera.look.x = math.wrap(g.camera.look.x, 360)
	g.camera.look.y = math.clamp(g.camera.look.y, -89, 89)

	look_mat := linalg.matrix4_from_yaw_pitch_roll_f32(to_radians(g.camera.look.x), to_radians(g.camera.look.y), 0)
	forward := ( look_mat * Vec4 {0,0,-1,1} ).xyz
	right := ( look_mat * Vec4 {1,0,0,1} ).xyz


	move_dir := forward * move_input.y + right * move_input.x

	motion := linalg.normalize0(move_dir) * MOVE_SPEED * dt
	g.camera.position += motion

	g.camera.target = g.camera.position + forward
}

mouse_move: Vec2

//stores the states for all keys
key_down: #sparse[sapp.Keycode]bool

//Events
event_cb :: proc "c" (ev: ^sapp.Event){
	context = default_context

	#partial switch ev.type{
		case .MOUSE_MOVE:
			mouse_move += {ev.mouse_dx, ev.mouse_dy}
		case .KEY_DOWN:
			key_down[ev.key_code] = true
		case .KEY_UP:
			key_down[ev.key_code] = false
	}
}

sg_range :: proc {
	sg_range_from_struct,
	sg_range_from_slice,
}

//proc for the sokol graphics range from struct(doesnt work with slices)
sg_range_from_struct :: proc(s: ^$T) -> sg.Range where intrinsics.type_is_struct(T) {
	return { 
		ptr = s, 
		size = size_of(T)
	 }
}

//function for the sokol graphics range from slice
sg_range_from_slice :: proc(s: []$T) -> sg.Range{
	return { 
		ptr = raw_data(s), 
		size = len(s) * size_of(s[0])
	 }
}

//proc for creating a new sprite on the screen and drawing it every frame
create_sprite :: proc(filename: cstring, pos2: Vec2, size: Vec2, id: cstring){

	WHITE :: sg.Color { 1,1,1,1 }



	// vertices
	vertices := []Vertex_Data {
		{ pos = { -(size.x/2), -(size.y/2), 0 }, col = WHITE, uv = {0,0} },
		{ pos = {  (size.x/2), -(size.y/2), 0 }, col = WHITE, uv = {1,0} },
		{ pos = { -(size.x/2),  (size.y/2), 0 },	col = WHITE, uv = {0,1} },
		{ pos = {  (size.x/2),  (size.y/2), 0 },	col = WHITE, uv = {1,1} },
	}

	append(&g.objects, Object{
		{pos2.x, pos2.y, 0},
		{0, 0, 0},
		load_image(filename),
		sg.make_buffer({ data = sg_range(vertices)}),
		id
	})
}

//proc for updating sprite
update_sprite :: proc(pos2: Vec2, rot3: Vec3, id: cstring){

	WHITE :: sg.Color { 1,1,1,1 }




	for &i in g.objects{
		if i.id == id{
			i.pos = {pos2.x, pos2.y, 0}
			i.rot = {rot3.x, rot3.y, rot3.z}
		}
	}
}