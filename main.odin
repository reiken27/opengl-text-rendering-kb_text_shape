package glfw_window

import fmt "core:fmt"
import m "core:math"
import os2 "core:os/os2"
import strings "core:strings"
import time "core:time"
import utf8 "core:unicode/utf8"
import ft "freetype"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import kbts "vendor:kb_text_shape"

WIDTH :: 1920
HEIGHT :: 1080
TITLE :: "My Window!"
font_size: u32 = 24

GL_MAJOR_VERSION :: 4
GL_MINOR_VERSION :: 6

character :: struct {
	textureid: u32,
	size:      [2]u32,
	bearing:   [2]i32,
	advance:   ft.Pos,
}

mat4 :: distinct matrix[4, 4]f32
characters: map[rune]character = {}
glyph_cache: map[u32]character = {}
notdef_glyph: character

vertex_shader_source :: `#version 330 core
layout (location = 0) in vec4 vertex; // <vec2 pos, vec2 tex>
out vec2 TexCoords;

uniform mat4 projection;

void main()
{
    gl_Position = projection * vec4(vertex.xy, 0.0, 1.0);
    TexCoords = vertex.zw;
}`


fragment_shader_source :: `#version 330 core
in vec2 TexCoords;
out vec4 color;

uniform sampler2D text;
uniform vec3 textColor;

void main()
{
    vec4 sampled = vec4(1.0, 1.0, 1.0, texture(text, TexCoords).r);
    color = vec4(textColor, 1.0) * sampled;
}`


orthographic :: proc(left, right, bottom, top, near, far: f32) -> mat4 {
	result := mat4{}

	result[0][0] = 2.0 / (right - left)
	result[1][1] = 2.0 / (top - bottom)
	result[2][2] = -2.0 / (far - near)
	result[3][3] = 1.0

	result[3][0] = -(right + left) / (right - left)
	result[3][1] = -(top + bottom) / (top - bottom)
	result[3][2] = -(far + near) / (far - near)

	return result
}

compile_shader :: proc(shader_source: string, shader_type: u32) -> u32 {
	shader := gl.CreateShader(shader_type)
	source_cstr := strings.clone_to_cstring(shader_source)
	defer delete(source_cstr)

	gl.ShaderSource(shader, 1, &source_cstr, nil)
	gl.CompileShader(shader)

	success: i32
	gl.GetShaderiv(shader, gl.COMPILE_STATUS, &success)
	if success == 0 {
		info_log: [512]u8
		gl.GetShaderInfoLog(shader, 512, nil, &info_log[0])
		fmt.eprintln("Shader compilation failed:", string(info_log[:]))
	}

	return shader
}

create_shader_program :: proc(vertex_source, fragment_source: string) -> u32 {
	vertex_shader := compile_shader(vertex_source, gl.VERTEX_SHADER)
	fragment_shader := compile_shader(fragment_source, gl.FRAGMENT_SHADER)

	program := gl.CreateProgram()
	gl.AttachShader(program, vertex_shader)
	gl.AttachShader(program, fragment_shader)
	gl.LinkProgram(program)

	success: i32
	gl.GetProgramiv(program, gl.LINK_STATUS, &success)
	if success == 0 {
		info_log: [512]u8
		gl.GetProgramInfoLog(program, 512, nil, &info_log[0])
		fmt.eprintln("Program linking failed:", string(info_log[:]))
	}

	gl.DeleteShader(vertex_shader)
	gl.DeleteShader(fragment_shader)

	return program
}

Shader :: struct {
	program: u32,
}

use_shader :: proc(s: ^Shader) {
	gl.UseProgram(s.program)
}

main :: proc() {
	if !glfw.Init() {
		fmt.eprintln("GLFW has failed to load.")
		return
	}
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR_VERSION)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR_VERSION)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	window_handle := glfw.CreateWindow(WIDTH, HEIGHT, TITLE, nil, nil)

	glfw.SetInputMode(window_handle, glfw.STICKY_KEYS, 1)

	defer glfw.Terminate()
	defer glfw.DestroyWindow(window_handle)
	if window_handle == nil {
		fmt.eprintln("GLFW has failed to load the window.")
		return
	}

	glfw.MakeContextCurrent(window_handle)
	gl.load_up_to(GL_MAJOR_VERSION, GL_MINOR_VERSION, glfw.gl_set_proc_address)

	// Load font with FreeType
	library: ft.Library
	ft_error := ft.init_free_type(&library)
	assert(ft_error == .Ok)
	defer ft.done_free_type(library)

	face: ft.Face
	ft.new_face(library, "NotoSansJP-Regular.ttf", 0, &face)
	defer ft.done_face(face)

	error := ft.set_pixel_sizes(face, 0, 24)
	if error != nil {
		fmt.eprintln("set pixel size")
		return
	}

	// Load font with kb_text_shape
	font_data, read_err := os2.read_entire_file_from_path(
		"NotoSansJP-Regular.ttf",
		context.allocator,
	)
	if read_err != nil {
		fmt.eprintln("Failed to read font file")
		return
	}
	defer delete(font_data)

	font, font_err := kbts.FontFromMemory(font_data, context.allocator)
	if font_err != nil {
		fmt.eprintln("Failed to load font with kb_text_shape")
		return
	}


	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	shader_program := create_shader_program(vertex_shader_source, fragment_shader_source)
	defer gl.DeleteProgram(shader_program)

	projection := orthographic(0.0, WIDTH, HEIGHT, 0, -1.0, 1.0)

	VAO: u32 = 0
	VBO: u32 = 0
	gl.GenVertexArrays(1, &VAO)
	gl.GenBuffers(1, &VBO)
	gl.BindVertexArray(VAO)
	gl.BindBuffer(gl.ARRAY_BUFFER, VBO)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(f32) * 6 * 4, nil, gl.DYNAMIC_DRAW)
	gl.EnableVertexAttribArray(0)
	gl.VertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, 4 * size_of(f32), cast(uintptr)0)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)
	shader := Shader {
		program = shader_program,
	}

	gl.UseProgram(shader.program)
	projection_loc := gl.GetUniformLocation(shader.program, "projection")
	gl.UniformMatrix4fv(projection_loc, 1, gl.FALSE, cast(^f32)&projection)
	scale: f32 = 1.0
	init_notdef_glyph(face)

	glfw.SwapInterval(0)

	for !glfw.WindowShouldClose(window_handle) {
		glfw.PollEvents()

		if glfw.GetKey(window_handle, glfw.KEY_1) != 0 {
			scale -= 0.1
		}
		if glfw.GetKey(window_handle, glfw.KEY_2) != 0 {
			scale += 0.1
		}
		if glfw.GetKey(window_handle, glfw.KEY_ESCAPE) != 0 {
			return
		}

		gl.ClearColor(0.25, 0.25, 0.25, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)

		for i in 0 ..< 45 {
			render_shaped_text(
				face,
				&font,
				&shader,
				"Hello world こんにちは 世界可愛いカタカナ", //Hello Worldこんにちは世界可い
				0.0,
				cast(f32)(cast(f32)i * cast(f32)font_size) * 1.5,
				scale,
				{1.0, 1.0, 1.0},
				VAO,
				VBO,
			)
		}

		glfw.SwapBuffers(window_handle)
	}
	delete(glyph_cache)

	gl.DeleteVertexArrays(1, &VAO)
	gl.DeleteBuffers(1, &VBO)
}

init_notdef_glyph :: proc(face: ft.Face) {
	err := ft.load_glyph(face, 0, ft.Load_Flags{.Render})
	if err != nil {
		fmt.eprintln("Failed to load .notdef glyph")
		return
	}

	texture: u32
	gl.GenTextures(1, &texture)
	gl.BindTexture(gl.TEXTURE_2D, texture)
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		gl.RED,
		cast(i32)face.glyph.bitmap.width,
		cast(i32)face.glyph.bitmap.rows,
		0,
		gl.RED,
		gl.UNSIGNED_BYTE,
		face.glyph.bitmap.buffer,
	)

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

	notdef_glyph = character {
		textureid = texture,
		size      = {face.glyph.bitmap.width, face.glyph.bitmap.rows},
		bearing   = {face.glyph.bitmap_left, face.glyph.bitmap_top},
		advance   = face.glyph.advance.x,
	}
}

load_glyph :: proc(face: ft.Face, glyph_id: u32) -> (character, bool) {

	if ch, ok := glyph_cache[glyph_id]; ok {
		return ch, true
	}
	err := ft.load_glyph(face, glyph_id, ft.Load_Flags{.Render})
	if err != nil {
		fmt.eprintln("ERROR::FREETYPE: Failed to load Glyph ID", glyph_id)
		return notdef_glyph, true
	}

	texture: u32
	gl.GenTextures(1, &texture)
	gl.BindTexture(gl.TEXTURE_2D, texture)
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		gl.RED,
		cast(i32)face.glyph.bitmap.width,
		cast(i32)face.glyph.bitmap.rows,
		0,
		gl.RED,
		gl.UNSIGNED_BYTE,
		face.glyph.bitmap.buffer,
	)

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

	char := character {
		textureid = texture,
		size      = {face.glyph.bitmap.width, face.glyph.bitmap.rows},
		bearing   = {face.glyph.bitmap_left, face.glyph.bitmap_top},
		advance   = face.glyph.advance.x,
	}

	glyph_cache[glyph_id] = char
	return char, true
}


window_render_text :: proc() {
	if !glfw.Init() {
		fmt.eprintln("GLFW has failed to load.")
		return
	}

	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR_VERSION)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR_VERSION)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

	window_handle := glfw.CreateWindow(WIDTH, HEIGHT, TITLE, nil, nil)
	glfw.SetInputMode(window_handle, glfw.STICKY_KEYS, 1)

	defer glfw.Terminate()
	defer glfw.DestroyWindow(window_handle)

	if window_handle == nil {
		fmt.eprintln("GLFW has failed to load the window.")
		return
	}

	glfw.MakeContextCurrent(window_handle)
	gl.load_up_to(GL_MAJOR_VERSION, GL_MINOR_VERSION, glfw.gl_set_proc_address)

	library: ft.Library
	ft_error := ft.init_free_type(&library)
	assert(ft_error == .Ok)

	face: ft.Face
	ft.new_face(library, "fonts/NotoSansJP-Regular.ttf", 0, &face)
	error := ft.set_pixel_sizes(face, 0, cast(u32)font_size)
	if error != nil {
		fmt.eprintln("set pixel size")
		return
	}

	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)

	for c := 32; c < 150; c += 1 {
		err := ft.load_char(face, cast(u64)c, ft.Load_Flags{.Render})
		if err != nil {
			fmt.eprintln("ERROR::FREETYPE: Failed to load Glyph for character", c)
			continue
		}

		texture: u32
		gl.GenTextures(1, &texture)
		gl.BindTexture(gl.TEXTURE_2D, texture)
		gl.TexImage2D(
			gl.TEXTURE_2D,
			0,
			gl.RED,
			cast(i32)face.glyph.bitmap.width,
			cast(i32)face.glyph.bitmap.rows,
			0,
			gl.RED,
			gl.UNSIGNED_BYTE,
			face.glyph.bitmap.buffer,
		)

		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

		char := character {
			textureid = texture,
			size      = {face.glyph.bitmap.width, face.glyph.bitmap.rows},
			bearing   = {face.glyph.bitmap_left, face.glyph.bitmap_top},
			advance   = face.glyph.advance.x,
		}

		characters[cast(rune)c] = char
	}
	ft.done_face(face)
	ft.done_free_type(library)

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	shader_program := create_shader_program(vertex_shader_source, fragment_shader_source)
	defer gl.DeleteProgram(shader_program)

	projection := orthographic(0.0, WIDTH, HEIGHT, 0, -1.0, 1.0)

	VAO: u32 = 0
	VBO: u32 = 0
	gl.GenVertexArrays(1, &VAO)
	gl.GenBuffers(1, &VBO)
	gl.BindVertexArray(VAO)
	gl.BindBuffer(gl.ARRAY_BUFFER, VBO)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(f32) * 6 * 4, nil, gl.DYNAMIC_DRAW)
	gl.EnableVertexAttribArray(0)
	gl.VertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, 4 * size_of(f32), cast(uintptr)0)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)

	shader := Shader {
		program = shader_program,
	}

	gl.UseProgram(shader.program)
	projection_loc := gl.GetUniformLocation(shader.program, "projection")
	gl.UniformMatrix4fv(projection_loc, 1, gl.FALSE, cast(^f32)&projection)
	scale: f32 = 1.0

	for !glfw.WindowShouldClose(window_handle) {
		glfw.PollEvents()
		if glfw.GetKey(window_handle, glfw.KEY_1) != 0 {
			scale -= 0.1
		}
		if (glfw.GetKey(window_handle, glfw.KEY_2) != 0) {
			scale += 0.1
		}

		if glfw.GetKey(window_handle, glfw.KEY_ESCAPE) != 0 {
			return
		}
		gl.ClearColor(0.25, 0.25, 0.25, 1.0)
		gl.Clear(gl.COLOR_BUFFER_BIT)


		glfw.SwapBuffers(window_handle)

	}

	// Cleanup
	gl.DeleteVertexArrays(1, &VAO)
	gl.DeleteBuffers(1, &VBO)
}

render_shaped_text :: proc(
	face: ft.Face,
	font: ^kbts.font,
	shader: ^Shader,
	text: string,
	x: f32,
	y: f32,
	scale: f32,
	color: [3]f32,
	vao: u32,
	vbo: u32,
) {
	use_shader(shader)
	gl.BindVertexArray(vao)

	color_loc := gl.GetUniformLocation(shader.program, "textColor")
	gl.Uniform3f(color_loc, color.x, color.y, color.z)
	gl.ActiveTexture(gl.TEXTURE0)

	runes := utf8.string_to_runes(text, context.temp_allocator)

	// Segment and shape the text
	Run :: struct {
		start:     u32,
		end:       u32,
		script:    kbts.script,
		direction: kbts.direction,
	}
	runs := make([dynamic]Run, context.temp_allocator)

	current_run: Run
	current_run.script = kbts.script.DONT_KNOW
	current_run.direction = kbts.direction.NONE

	break_state: kbts.break_state
	kbts.BeginBreak(&break_state, kbts.direction.NONE, kbts.japanese_line_break_style.NORMAL)


	for rune, i in runes {
		is_last: b32 = i == (len(runes) - 1)
		kbts.BreakAddCodepoint(&break_state, rune, 1, is_last)

		break_t: kbts.break_type
		for kbts.Break(&break_state, &break_t) {
			// Always update the end position first
			current_run.end = break_t.Position

			if kbts.break_flag.SCRIPT in break_t.Flags ||
			   kbts.break_flag.DIRECTION in break_t.Flags {
				// Save the current run if it has content
				if current_run.end > current_run.start {
					append(&runs, current_run)
				}
				// Start a new run at this position
				current_run.start = break_t.Position
				current_run.script = break_t.Script
				current_run.direction = break_t.Direction
			}
		}
	}

	if current_run.end > current_run.start {
		append(&runs, current_run)
	}
	kbts.BreakFlush(&break_state)

	// // Normalize NONE directions to LTR
	// for &run in runs {
	// 	if run.direction == kbts.direction.NONE {
	// 		run.direction = kbts.direction.LTR
	// 	}
	// }

	// Shape and render each run
	state, alloc_err := kbts.CreateShapeState(font, context.allocator)

	cursor_x := x
	cursor_y := y

	x_scale := cast(f32)face.size.metrics.x_scale / cast(f32)(1 << 16)
	y_scale := cast(f32)face.size.metrics.y_scale / cast(f32)(1 << 16)

	for run in runs {
		run_start_x := cursor_x
		run_start_y := cursor_y

		run_runes := runes[run.start:run.end]
		glyphs := make([dynamic]kbts.glyph, context.temp_allocator)

		for rune in run_runes {
			glyph := kbts.CodepointToGlyph(font, rune)
			append(&glyphs, glyph)
		}

		// Shape the glyphs
		config := kbts.ShapeConfig(font, run.script, kbts.language.DONT_KNOW)
		glyph_count := u32(len(glyphs))
		glyph_capacity := glyph_count * 2

		for kbts.Shape(
			    state,
			    &config,
			    run.direction,
			    run.direction,
			    raw_data(glyphs),
			    &glyph_count,
			    glyph_capacity,
		    ) {
			new_capacity := state.RequiredGlyphCapacity
			if new_capacity == 0 || new_capacity <= glyph_capacity {
				break
			}
			glyph_capacity = new_capacity
			resize(&glyphs, int(glyph_capacity))
		}

		resize(&glyphs, int(glyph_count))

		// Render positioned glyphs
		cursor := kbts.Cursor(run.direction)

		for i in 0 ..< glyph_count {
			glyph := &glyphs[i]

			// Get position from kb_text_shape (in font units)
			glyph_x, glyph_y := kbts.PositionGlyph(&cursor, glyph)

			// Load glyph for each instance (don't skip rendering duplicates)
			ch: character
			if glyph.Id == 0 {
				ch = notdef_glyph
			} else {
				ch_loaded, ok := load_glyph(face, cast(u32)glyph.Id)
				if ok {
					ch = ch_loaded
				} else {
					ch = notdef_glyph
				}
			}

			// Convert font units to 26.6 fractional pixels using FreeType metrics
			// Then convert to actual pixels by dividing by 64
			pixel_x := (cast(f32)glyph_x * x_scale) / 64.0
			pixel_y := (cast(f32)glyph_y * y_scale) / 64.0

			xpos := run_start_x + pixel_x * scale + cast(f32)ch.bearing.x * scale
			ypos := run_start_y + pixel_y * scale - cast(f32)ch.bearing.y * scale

			w := cast(f32)ch.size.x * scale
			h := cast(f32)ch.size.y * scale

			vertices: [6][4]f32 = {
				{xpos, ypos + h, 0.0, 1.0},
				{xpos, ypos, 0.0, 0.0},
				{xpos + w, ypos, 1.0, 0.0},
				{xpos, ypos + h, 0.0, 1.0},
				{xpos + w, ypos, 1.0, 0.0},
				{xpos + w, ypos + h, 1.0, 1.0},
			}

			gl.BindTexture(gl.TEXTURE_2D, ch.textureid)
			gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
			gl.BufferSubData(gl.ARRAY_BUFFER, 0, size_of(f32) * 24, &vertices)
			gl.BindBuffer(gl.ARRAY_BUFFER, 0)
			gl.DrawArrays(gl.TRIANGLES, 0, 6)
		}

		// Update cursor for next run - cursor.X/Y contains the final position after this run
		cursor_x = run_start_x + (cast(f32)cursor.X * x_scale) / 64.0 * scale
		cursor_y = run_start_y + (cast(f32)cursor.Y * y_scale) / 64.0 * scale

		// Reset shape state for next run
		kbts.ResetShapeState(state)
	}

	gl.BindVertexArray(0)
	gl.BindTexture(gl.TEXTURE_2D, 0)
}

// test_breaks :: proc() {
// 	string_test := "Hello, こんにちは!"
// 	data, err := os2.read_entire_file_from_path("fonts/NotoSansJP-Regular.ttf", context.allocator)
// 	if err != nil {
// 		return
// 	}
// 	font, errfont := kbts.FontFromMemory(data, context.allocator)
// 	script := kbts.script.DONT_KNOW
// 	direction := kbts.direction.NONE
// 	break_state: kbts.break_state
// 	kbts.BeginBreak(&break_state, direction, kbts.japanese_line_break_style.NORMAL)
// 	for rune, i in string_test {
// 		is_last: b32 = i == (strings.rune_count(string_test) - 1)
// 		break_t: kbts.break_type
// 		kbts.BreakAddCodepoint(&break_state, rune, 1, is_last)
// 		for kbts.Break(&break_state, &break_t) {
// 			fmt.print("Flags ", break_t.Flags, "\n")
// 			if kbts.break_flag.DIRECTION in break_t.Flags {
// 				fmt.print("DIRECTION,")
// 			}
// 			if kbts.break_flag.SCRIPT in break_t.Flags {
// 				fmt.print("SCRIPT,")
// 			}
// 			if kbts.break_flag.GRAPHEME in break_t.Flags {
// 				fmt.print("GRAPHEME,")
// 			}
// 			if kbts.break_flag.WORD in break_t.Flags {
// 				fmt.print("WORD,")
// 			}
// 			if kbts.break_flag.LINE_SOFT in break_t.Flags {
// 				fmt.print("LINE SOFT,")
// 			}
// 			if kbts.break_flag.LINE_HARD in break_t.Flags {
// 				fmt.print("LINE HARD,")
// 			}
// 			fmt.println()
// 		}
// 	}
// 	kbts.BreakFlush(&break_state)
// }
