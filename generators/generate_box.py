
briq_data = {
    1: {
        0x1: 54
    },
    2: {
        0x1: 20,
        0x3: 10
    }
}

shape_data = {
    0x1: "0xcafe",
    0x2: "0xdead",
}

attributes_registry_address = 0xcafe
briq_address = 0xdead

def generate_box(briq_data=briq_data, shape_data=shape_data, attributes_registry_address=attributes_registry_address, briq_address=briq_address):
    lines = []

    lines.append(f"const attributes_registry_address = {attributes_registry_address};")
    lines.append(f"const briq_address = {briq_address};")

    lines.append("briq_data_start:")
    i = 1
    for key in briq_data:
        if key != i:
            print("Bad briq_data")
            raise
        lines.append(f'dw {briq_data[key][0x1] if 0x1 in briq_data[key] else 0};')
        lines.append(f'dw {briq_data[key][0x3] if 0x3 in briq_data[key] else 0};')
        lines.append(f'dw {briq_data[key][0x4] if 0x4 in briq_data[key] else 0};')
        lines.append(f'dw {briq_data[key][0x5] if 0x5 in briq_data[key] else 0};')
        lines.append(f'dw {briq_data[key][0x6] if 0x6 in briq_data[key] else 0};')
        i += 1
    lines.append("briq_data_end:")
    lines.append("shape_data_start:")
    j = 1
    for key in shape_data:
        if key != j:
            print("Bad shape_data")
            raise
        lines.append(f'dw {shape_data[key]};')
        j += 1
    if j != i:
        print("Bad shape/briq data match")
        raise
    lines.append("shape_data_end:")

    return '%lang starknet\n' + '\n'.join(lines) + '\n'
