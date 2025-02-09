
@group(0) @binding(0) var<uniform> window_size: vec2f;
@group(0) @binding(1) var<storage> camera: Camera;
@group(0) @binding(2) var<storage> spheres: array<Sphere>;
@group(0) @binding(3) var<uniform> spheres_len: u32;

const inf: f32 = 3.4028235e+38;

const MATERIAL_LAMBERTIAN: u32 = 0;
const MATERIAL_METAL: u32 = 1;
const MATERIAL_DIELECTRIC: u32 = 2;

struct Camera {
    samples_per_pixel: u32,
    max_depth: u32,
    vfov: f32,
    look_from: Position,
    look_at: Position,
    v_up: Position,
    defocus_angle: f32,
    focus_dist: f32,
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

const pi: f32 = 3.14159265358979323846264338327950288419716939937510;

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
fn RandomUnitVec3f(seed: ptr<function, u32>) -> vec3f {
    let xy = gaussian(seed);
    let z = gaussian(seed).y;

    let rand_vec = normalize(vec3f(xy, z));

    return rand_vec;

}

fn degreesToRadians(degrees: f32) -> f32 {
    return degrees * pi / 180;
}

fn RandomVec3fOnHemisphere(normal: vec3f, seed: ptr<function, u32>) -> vec3f {
    let rand_vec = RandomUnitVec3f(seed);
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


fn nearZero(v: vec3f) -> bool {
    let s = f32(1e-8);

    return abs(v.x) < s && abs(v.y) < s && abs(v.z) < s;
}

fn reflect(v: vec3f, n: vec3f) -> vec3f {
    return v - 2.0 * dot(v, n) * n;
}

fn refract(uv: vec3f, n: vec3f, etai_over_etat: f32) -> vec3f {
    let cos_theta = min(dot(-uv, n), 1.0);

    let r_out_perp = etai_over_etat * (uv + cos_theta * n);

    let r_out_perp_len = length(r_out_perp);

    let r_out_perp_len_squared = r_out_perp_len * r_out_perp_len;

    let r_out_parallel = -sqrt(abs(1.0 - r_out_perp_len_squared)) * n;

    return r_out_perp + r_out_parallel;

}

// Use Schlick's approximation for reflectance.
fn reflectance(cosine: f32, ri: f32) -> f32 {

    var r0 = (1.0 - ri) / (1.0 + ri);
    r0 = r0 * r0;

    return r0 + (1.0 - r0) * pow(1.0 - cosine, 5.0);
}

fn Vec3fFromColor(color: Color) -> vec3f {
    return vec3f(color.r, color.g, color.b);

}

fn scatter(
    ray: Ray, 
    rec: ptr<function, HitRecord>, 
    attenuation: ptr<function, vec3f>, 
    scattered: ptr<function, Ray>, 
    seed: ptr<function, u32>
) -> bool {

    switch (*rec).material {

        case MATERIAL_LAMBERTIAN: {
            let albedo = Vec3fFromColor((*rec).material_color);
            var scatter_dir = (*rec).normal + RandomUnitVec3f(seed);

            if nearZero(scatter_dir) {
                scatter_dir = (*rec).normal;
            }
        
            (*scattered) = Ray((*rec).p, scatter_dir);
            (*attenuation) = albedo;

            return true;
        }

        case MATERIAL_METAL: {

            let albedo = Vec3fFromColor((*rec).material_color);
            var reflected = reflect(ray.dir, (*rec).normal);

            let fuzz = (*rec).fuzz;
            reflected = normalize(reflected) + (fuzz * RandomUnitVec3f(seed));

                
            (*scattered) = Ray((*rec).p, reflected);
            
            (*attenuation) = albedo;

            return true;
        }

        case MATERIAL_DIELECTRIC: {
            
            let refraction_index = (*rec).refraction_index;
            var ri: f32;
                
            if (*rec).front_face {
                ri = 1.0 / refraction_index;
            } else {
                ri = refraction_index;
            }

            let unit_dir = normalize(ray.dir);

            let cos_theta = min(dot(-unit_dir, (*rec).normal), 1.0);
            let sin_theta = sqrt(1.0 - cos_theta * cos_theta);

            let cannot_refract = ri * sin_theta > 1.0;

            var dir: vec3f;

            let can_reflect = reflectance(cos_theta, ri) > random(seed);

            if cannot_refract || can_reflect {
                dir = reflect(unit_dir, (*rec).normal);
            } else {
                dir = refract(unit_dir, (*rec).normal, ri);
            }
            
            (*scattered) = Ray((*rec).p, dir);
            (*attenuation) = vec3f(1, 1, 1);
        
            return true;

        }
        
        default: {
            //panic(); 
            return false;
        }

    }


}

fn getRayColor(ray: Ray, seed: ptr<function, u32>) -> vec3f {

    var color = vec3f(1, 1, 1);

    var r = ray;
    for (var i: u32 = 0; i < camera.max_depth; i++) {

        var rec: HitRecord;

        if hitWorld(r, 0.0001, inf, &rec) {
            var scattered: Ray;
            var attenuation: vec3f;

            if scatter(r, &rec, &attenuation, &scattered, seed) {
                color *= attenuation;
                r = scattered;
            } else {
                break;
            }

           // return 0.5 * (rec.normal + 1.0); // fine colored sphere, chapter 6


            

        } else {

            let unit_dir = normalize(r.dir);
            let a = 0.5 * (unit_dir.y + 1.0);

            color *= (1.0 - a) * vec3f(1.0, 1.0, 1.0) + a * vec3f(0.5, 0.7, 1.0);
            return color;

        }
    }

    return color;

}

/// Causes the gpu to hang, probably not the smartest way to do it
fn panic() {
    while(true) {

    }

}
struct HitRecord {
    p: vec3f,
    normal: vec3f,
    t: f32,
    front_face: bool,
    material: u32,
    material_color: Color,
    fuzz: f32,
    refraction_index: f32
}

fn hitWorld(ray: Ray, t_min: f32, t_max: f32, record: ptr<function, HitRecord>) -> bool {
    if spheres_len < 1 { // out of bounds array check
        //(*record).normal = vec3f(1.0, 0.0, 0.0);
        panic();
        return true;
    };

    var temp_rec: HitRecord;
    var hit_anything: bool = false;
    var closest = t_max;

    for (var i: u32 = 0; i < spheres_len; i++) {
        let sphere = spheres[i];

        if hitSphere(sphere, ray, t_min, closest, &temp_rec) {
            hit_anything = true;
            closest = temp_rec.t;
            (*record) = temp_rec;
        }

    }

    return hit_anything;

}

struct Position {
    x: f32,
    y: f32,
    z: f32
}

fn Vec3fFromPosition(pos: Position) -> vec3f {
    return vec3f(pos.x, pos.y, pos.z);
}

struct Color {
    r: f32,
    g: f32,
    b: f32
}

struct Sphere {
    center: Position, // why no vec3f? it caused alignment problems since it has align of 16
    radius: f32,
    material: u32,
    color: Color,
    fuzz: f32,
    refraction_index: f32
}

fn hitSphere(sphere: Sphere, ray: Ray, t_min: f32, t_max: f32, rec: ptr<function, HitRecord>) -> bool {

    let sphere_center = vec3f(sphere.center.x, sphere.center.y, sphere.center.z);
    let oc = sphere_center - ray.orig;

    let a = pow(length(ray.dir), 2.0); // length squared
    let h = dot(ray.dir, oc);
    let c = pow(length(oc), 2.0) - sphere.radius * sphere.radius;

    let discriminant = h * h - a * c;

    if discriminant < 0 {
        return false;
    }


    let sqrt_discr = sqrt(discriminant);

    var root = (h - sqrt_discr) / a;
    if root <= t_min || t_max <= root {
        root = (h + sqrt_discr) / a;

        if root <= t_min || t_max <= root{
            return false;
        }
    }

    (*rec).t = root;
    (*rec).p = rayAt(ray, (*rec).t);

    let outward_normal = ((*rec).p - sphere_center) / sphere.radius;
    (*rec).front_face = dot(ray.dir, outward_normal) < 0.0;
    (*rec).material = sphere.material;
    (*rec).material_color = sphere.color;
    (*rec).fuzz = sphere.fuzz;
    (*rec).refraction_index = sphere.refraction_index;

    if (*rec).front_face {
        (*rec).normal = outward_normal;
    } else {
        (*rec).normal = -outward_normal;
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

fn RandomVec3InUnitDisk(seed: ptr<function, u32>) -> vec3f {
    let theta = randomInRange(seed, 0, 2 * pi);
    let r = random(seed);

    return vec3f(r * cos(theta), r * sin(theta), 0);
}

/// return f32 in [0, 1)
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

    let theta = degreesToRadians(camera.vfov);

    let camera_center = Vec3fFromPosition(camera.look_from);

    let camera_dir = camera_center - Vec3fFromPosition(camera.look_at);
    //let camera_focal_length = length(camera_dir);


    let h = tan(theta / 2);
    let viewport_height = 2 * h * camera.focus_dist;
    let viewport_width = viewport_height * (window_size.x / window_size.y);

    let w = normalize(camera_dir);
    let u = normalize(cross(Vec3fFromPosition(camera.v_up), w));
    let v = cross(w, u);

    // Calculate the vectors across the horizontal and down the vertical viewport edges.
    let viewport_u = viewport_width * u;
    let viewport_v = viewport_height * (-v);
    
    // Calculate the horizontal and vertical delta vectors to the next pixel.
    let pixel_delta_u = viewport_u / window_size.x;
    let pixel_delta_v = viewport_v / window_size.y;

    // Calculate the location of the upper left pixel.
    let view_port_upper_left = camera_center - (camera.focus_dist * w) 
        - viewport_u / 2.0 - viewport_v / 2.0;

    let pixel_00_loc = view_port_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v);
    
    // Calculate the camera defocus disk basis vectors.
    let defocus_radius = camera.focus_dist * tan(degreesToRadians(camera.defocus_angle / 2));
    var defocus_disk_u = u * defocus_radius;
    var defocus_disk_v = v * defocus_radius;
    
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

        if camera.defocus_angle <= 0 {
            ray.orig = camera_center;
        } else {
            var p = RandomVec3InUnitDisk(&seed);
            ray.orig = camera_center + (p.x * defocus_disk_u) + (p.y * defocus_disk_v);
        }
        ray.dir = pixel_center - ray.orig;

        color += getRayColor(ray, &seed);


    }

    // checking randomness function, look random lol
    //var seed = cantorPair2(x, y);
    //let r1 = random(&seed);
    //return vec4f(r1, r1, r1, 1);

    color = color / f32(camera.samples_per_pixel);
    // sqrt = gamma of 2 
    return vec4f(color, 1);

}




