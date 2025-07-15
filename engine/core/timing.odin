package core

import "core:time"
import "core:fmt"

TimeContext :: struct {
    start: time.Time,
    current: time.Time,
    previous: time.Time,  
    timeElapsed: f32,
    deltaTime: f32,
}

init :: proc() -> ^TimeContext {
    tc := TimeContext{
        start = time.now(),
        current = time.now(),
        previous = time.now(),
        timeElapsed = 0.0,
        deltaTime = 0.0,
    }
    return new_clone(tc)
}

update :: proc(tc: ^TimeContext) {
    now := time.now()
    tc.previous = tc.current
    tc.current = now

    raw_ns := time.diff(tc.previous, now)
    tc.deltaTime = cast(f32)time.duration_seconds(raw_ns)
    tc.timeElapsed = cast(f32)time.duration_seconds(time.diff(tc.start, now))


    //fmt.printf("Frame time: %.6f seconds (%.1f FPS)\n", 
    //    tc.deltaTime,
    //    1.0 / tc.deltaTime
    //)
} 

end :: proc(tc: ^TimeContext) {
    free(tc)
}