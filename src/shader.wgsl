
@group(0) @binding(0) var<uniform> window_size: vec2f;
@group(0) @binding(1) var<uniform> camera: Camera;
@group(0) @binding(2) var<storage> spheres: array<Sphere>;
@group(0) @binding(3) var<uniform> spheres_len: u32;

const inf: f32 = 3.4028235e+38;

struct Camera {
    center: vec3f,
    focal_length: f32,
    view_port: vec2f,
    samples_per_pixel: u32,
    max_depth: u32
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

//fn RandomVec3f(seed: u32, min: f32, max: f32) -> vec3f {
//    return vec3f(
//        randomInRange(seed + 1, min, max),
//        randomInRange(seed + 2, min, max),
//        randomInRange(seed + 3, min, max)
//    );
//}

const pi: f32= 3.14159265358979323846264338327950288419716939937510;

// https://en.wikipedia.org/wiki/Box%E2%80%93Muller_transform
fn gaussian(seed: ptr<function, u32>) -> vec2f {
    let u1 = random(seed);
    let u2 = random(seed);

    let z1 = sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
    let z2 = sqrt(-2.0 * log(u1)) * sin(2.0 * pi * u2);

    return vec2f(z1, z2);

}


// solution in source absolutely killed performance
// one can generate point on unit sphere by sampling 3 gaussian random variables.
// https://mathworld.wolfram.com/SpherePointPicking.html
fn RandomVec3fOnHemisphere(normal: vec3f, seed: ptr<function, u32>) -> vec3f {
    let xy = gaussian(seed);
    let z = gaussian(seed).y;

    let rand_vec = normalize(vec3f(xy, z));

    // ensure its in right hemisphere
    if dot(rand_vec, normal) < 0.0 {
        return rand_vec;
    } else {
        return -1.0 * rand_vec;
    }
}

fn rayAt(ray: Ray, t: f32) -> vec3f {
    return ray.orig + t * ray.dir;
}

fn getRayColor(ray: Ray, seed: ptr<function, u32>) -> vec3f {

    var color = vec3f(1, 1, 1);

    var r = ray;
    for (var i: u32 = 0; i < camera.max_depth; i++) {

        var rec: HitRecord;

        if hitWorld(r, 0.0001, inf, &rec) {

            let direction = rec.normal + RandomVec3fOnHemisphere(rec.normal, seed);
            r = Ray(rec.p, direction);
            //return 0.5 * (rec.normal + 1.0);
            //return RandomVec3fOnHemisphere(rec.normal, seed);
            color *= 0.5;

        } else {

            let unit_dir = normalize(r.dir);
            let a = 0.5 * (unit_dir.y + 1.0);

            color *= (1.0 - a) * vec3f(1.0, 1.0, 1.0) + a * vec3f(0.5, 0.7, 1.0);
            return color;

        }
    }

    return color;

}

fn panic() {
    while(true) {

    }

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
        (*rec).normal = -1.0 * outward_normal;
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
fn rand_lcg(seed: u32) -> u32 {
    let rng_state: u32 = 1664525 * seed + 1013904223;

    let r0 = randXORShift(rng_state);
    let r1 = randXORShift(r0);

    return randXORShift(r1);

}

fn random(seed: ptr<function, u32>) -> f32 {
    (*seed) = rand_lcg((*seed));

    let f0 = f32(rand_lcg((*seed))) * (1.0 / 4294967296.0);
    return f0;

}

fn randomInRange(seed: ptr<function, u32>, min: f32, max: f32) -> f32 {
    return min + (max - min) * random(seed);
}

@vertex
fn vs_main(in: VertexIn) -> VertexOut {

    var out: VertexOut;
    out.position = vec4f(in.position, 0, 1);

    return out;

}

fn cantorPair2(x: u32, y: u32) -> u32 {
    return ((x + y) * (x + y + 1)) / 2 + y;
}

fn cantorPair3(x: u32, y: u32, z: u32) -> u32 {
    return cantorPair2(cantorPair2(x, y), z);
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

    let x = u32(in.position.x * window_size.x);
    let y = u32(in.position.y * window_size.y);

    var color = vec3f(0, 0, 0);

    for (var sample: u32 = 0; sample < camera.samples_per_pixel; sample++) {

        var seed = cantorPair3(x, y, sample);

        //let offset = vec2f(0, 0); // turn off anti aliasing
        let r1 = random(&seed);
        let r2 = random(&seed);

        let offset = vec2f(r1 - 0.5, r2 - 0.5); 

        let pixel_center = pixel_00_loc 
            + (in.position.x + offset.x) * pixel_delta_u 
            + (in.position.y + offset.y) * pixel_delta_v;

        var ray: Ray;
        ray.orig = camera.center;
        ray.dir = pixel_center - camera.center;

        color += getRayColor(ray, &seed);


    }

    // checking randomness function, look random lol
    //var seed = cantorPair2(x, y);
    //let r1 = random(&seed);
    //return vec4f(r1, r1, r1, 1);

    color = color / f32(camera.samples_per_pixel);
    return vec4f(color, 1);

}




