package app

import sdl "vendor:sdl2"
import "core:fmt"
import "core:time"


App :: struct {
    renderer: Renderer,
    pass: Pass,
    start_time: time.Time,
}

init :: proc(app: ^App) -> bool {
    app.start_time = time.now()

    if !init_renderer(&app.renderer, "Ocin", WINDOW_WIDTH, WINDOW_HEIGHT, app.start_time) {
        fmt.eprintln("render failed")
        return false
    }
    fmt.println("Render initiated")

    if !init_swapchain(&app.renderer) {
        fmt.eprintln("swap failed")
        return false
    }
    fmt.println("Swap initiated")

    t(.BEGIN, "create mesh")
    create_mesh_from_glb(&app.renderer, "glbs/BoxTextured.gltf")
    t(.END, "create mesh")
    
    t(.BEGIN, "pass"); defer t(.END, "pass")
    init_pass(&app.renderer)

    t(.BEGIN, "camera"); defer t(.END, "camera")
    init_camera(&app.renderer)

    return true
}

run :: proc(app: ^App) {
    main_loop: for {
        event: sdl.Event
        for sdl.PollEvent(&event) {
            #partial switch event.type {
                case .QUIT:
                    break main_loop 
                case .KEYDOWN:
                    #partial switch event.key.keysym.sym {
                        case .ESCAPE:
                            break main_loop
                    }
                }
            }
        }

    draw_frame(&app.renderer)
}


exit :: proc(app: ^App) {
    destroy_renderer(&app.renderer)
}

main :: proc() {
    app: App
    defer exit(&app)

    if !init(&app) {
        fmt.eprintln("Failed to initialize application")
        return
    }

    run(&app)
}
