
@group(0) @binding(0) var<uniform> window_size: vec2f;
@group(0) @binding(1) var<uniform> camera: Camera;
@group(0) @binding(2) var<storage> spheres: array<Sphere>;
@group(0) @binding(3) var<uniform> spheres_len: u32;

const inf: f32 = 3.4028235e+38;

struct Camera {
    center: vec3f,
    focal_length: f32,
    view_port: vec2f
}

struct VertexIn {
    @location(0) position: vec2f,
}

struct VertexOut {
    @builtin(position) position: vec4f,
}

struct Ray {
    orig: vec3f,
    dir: vec3f
}

fn rayAt(ray: Ray, t: f32) -> vec3f {
    return ray.orig + t * ray.dir;
}

fn getRayColor(ray: Ray) -> vec3f {

    var rec: HitRecord;

    if hitWorld(ray, 0, inf, &rec) {
        return 0.5 * (rec.normal + 1);
    }


    let unit_dir = normalize(ray.dir);
    let a = 0.5 * (unit_dir.y + 1.0);
    return (1.0 - a) * vec3f(1.0, 1.0, 1.0) + a * vec3f(0.5, 0.7, 1.0);

}

struct HitRecord {
    p: vec3f,
    normal: vec3f,
    t: f32,
    front_face: bool
}

fn hitWorld(ray: Ray, t_min: f32, t_max: f32, record: ptr<function, HitRecord>) -> bool {
    if spheres_len < 1 { // out of bounds array check
        (*record).normal = vec3f(1.0, 0.0, 0.0);
        return true;
    };

    var temp_rec: HitRecord;
    var hit_anything: bool = false;
    var closest = t_max;

    for (var i: u32 = 0; i < spheres_len; i++) {
        let sphere = spheres[i];

        if hitSphere(sphere, ray, t_min, t_max, &temp_rec) {
            hit_anything = true;
            closest = temp_rec.t;
            (*record) = temp_rec;
        }

    }

    return hit_anything;

}

struct Sphere {
    center: vec3f,
    radius: f32
}

fn hitSphere(sphere: Sphere, ray: Ray, t_min: f32, t_max: f32, rec: ptr<function, HitRecord>) -> bool {

    let oc = sphere.center - ray.orig;

    let a = pow(length(ray.dir), 2.0); // length squared
    let h = dot(ray.dir, oc);
    let c = pow(length(oc), 2.0) - sphere.radius * sphere.radius;

    let discriminant = h * h - a * c;

    if discriminant < 0 {
        return false;
    }


    let sqrt_discr = sqrt(discriminant);

    var root = (h - sqrt_discr) / a;
    if root <= t_min || t_max < root {
        root = (h + sqrt_discr) / a;

        if root <= t_min || t_max <= root{
            return false;
        }
    }

    (*rec).t = root;
    (*rec).p = rayAt(ray, (*rec).t);

    let outward_normal = ((*rec).p - sphere.center) / sphere.radius;
    (*rec).front_face = dot(ray.dir, outward_normal) < 0.0;

    if (*rec).front_face {
        (*rec).normal = outward_normal;
    } else {
        (*rec).normal =  -1.0 * outward_normal;
    }

    return true;
}

fn randXORShift(rand_state: u32) -> u32 {
    // why these numbers? dno havent read the paper
    var r = rand_state;
    r ^= (r << u32(13));
    r ^= (r << u32(17));
    r ^= (r << u32(5));

    return r;
}

// super duper random number gen ;)
// https://www.reedbeta.com/blog/quick-and-easy-gpu-random-numbers-in-d3d11/
/// returns random f32 in [0, 1)
fn random(seed: u32) -> f32 {
    // rand_lcg
    let rng_state: u32 = 1664525 * seed + 1013904223;

    let r0 = randXORShift(rng_state);
    let r1 = randXORShift(r0);

    let f0 = f32(randXORShift(r1)) * (1.0 / 4294967296.0);

}

fn randomInRange(seed: u32, min: f32, max: f32) -> f32 {
    return min + (max - min) * random(seed);
}

@vertex
fn vs_main(in: VertexIn) -> VertexOut {

    var out: VertexOut;
    out.position = vec4f(in.position, 0, 1);

    return out;

}

@fragment
fn fs_main(in: VertexOut) -> @location(0) vec4f {

    let viewport_u = vec3(camera.view_port.x, 0, 0);
    let viewport_v = vec3(0, -camera.view_port.y, 0);
    
    let pixel_delta_u = viewport_u / window_size.x;
    let pixel_delta_v = viewport_v / window_size.y;

    let view_port_upper_left = camera.center - vec3f(0, 0, camera.focal_length) 
        - viewport_u / 2.0 - viewport_v / 2.0;

    let pixel_00_loc = view_port_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v);

    let pixel_center = pixel_00_loc 
        + in.position.x * pixel_delta_u 
        + in.position.y * pixel_delta_v;

    var ray: Ray;
    ray.orig = camera.center;
    ray.dir = pixel_center - camera.center;

    let color = getRayColor(ray);

    return vec4f(color, 1);

}




