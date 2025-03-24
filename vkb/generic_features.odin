package vk_bootstrap

// Core
import "core:mem"
import "core:reflect"

// Vendor
import vk "vendor:vulkan"

/* Assuming the total of bits from any extension feature. */
FEATURES_BITS_FIELDS_CAPACITY :: 256

Generic_Feature :: struct {
	type:   typeid,
	p_next: Generic_Feature_P_Next_Node,
}

Generic_Feature_P_Next_Node :: struct {
	sType:  vk.StructureType,
	pNext:  rawptr,
	fields: [FEATURES_BITS_FIELDS_CAPACITY]b32,
}

create_generic_features :: proc(features: ^$T) -> (v: Generic_Feature) {
	v.type = T
	mem.copy(&v.p_next, features, size_of(T))
	return
}

/* Check if all `requested` extension features bits is available. */
generic_features_match :: proc(
	requested: ^Generic_Feature,
	supported: ^Generic_Feature,
) -> (
	ok: bool,
) {
	assert(
		requested.p_next.sType == supported.p_next.sType,
		"Non-matching sTypes in features nodes!",
	)

	ok = true

	for i in 0 ..< FEATURES_BITS_FIELDS_CAPACITY {
		// Skip fields sType and pNext
		field := reflect.struct_field_at(requested.type, i + 2)
		// Check if there is no more features bits
		if field.name == "" {
			return
		}

		if requested.p_next.fields[i] && !supported.p_next.fields[i] {
			log_warnf(
				"Requested feature bit \x1b[33m%s\x1b[0m is missing for \x1b[33m%v\x1b[0m",
				field.name,
				requested.p_next.sType,
			)
			ok = false
		}
	}

	return
}
