#version 440

// The liquid step slider (VAS interaction): a rail of squircle slots, and a dot that merges into the slot it reaches. The merge is a smooth union of distance fields, the analytic form of the blur-and-threshold goo, so nothing half-transparent can be erased by a threshold.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float slotCount;
    float slotSize;
    float spacing;
    float dotPosition;
    float dotRadius;
    float blend;
    vec4 railColor;
    vec4 flowColor;
} ubuf;

float superLength(vec2 v, float n)
{
    v = max(v, vec2(0.0));
    return pow(pow(v.x, n) + pow(v.y, n), 1.0 / n);
}

float squircleDistance(vec2 point, vec2 halfSize, float cornerRadius)
{
    vec2 q = abs(point) - halfSize + vec2(cornerRadius);
    return superLength(q, 4.0) + min(max(q.x, q.y), 0.0) - cornerRadius;
}

float smoothUnion(float first, float second, float k)
{
    float h = max(k - abs(first - second), 0.0) / k;
    return min(first, second) - h * h * k * 0.25;
}

void main()
{
    vec2 pixel = qt_TexCoord0 * ubuf.itemSize;
    float centerY = ubuf.itemSize.y * 0.5;
    float startX = (ubuf.itemSize.x - (ubuf.slotCount - 1.0) * ubuf.spacing) * 0.5;
    float halfSlot = ubuf.slotSize * 0.5;

    float rail = 1e5;
    float flow = length(pixel - vec2(startX + ubuf.dotPosition * ubuf.spacing, centerY)) - ubuf.dotRadius;
    for (int index = 0; index < 8; ++index) {
        if (float(index) >= ubuf.slotCount)
            break;
        vec2 center = vec2(startX + float(index) * ubuf.spacing, centerY);
        rail = min(rail, squircleDistance(pixel - center, vec2(halfSlot), halfSlot * 0.55));
        // Size is the only variable: a slot the dot has reached is full size, one a whole step away is nothing at all.
        float reach = max(0.0, 1.0 - abs(ubuf.dotPosition - float(index)));
        if (reach > 0.001)
            flow = smoothUnion(flow, squircleDistance(pixel - center, vec2(halfSlot * reach), halfSlot * 0.55 * reach), ubuf.blend);
    }

    vec4 color = ubuf.railColor * clamp(0.5 - rail, 0.0, 1.0);
    vec4 liquid = ubuf.flowColor * clamp(0.5 - flow, 0.0, 1.0);
    fragColor = (liquid + color * (1.0 - liquid.a)) * ubuf.qt_Opacity;
}
