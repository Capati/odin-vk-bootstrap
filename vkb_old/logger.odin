package vk_bootstrap

// Core
import "core:fmt"
import "core:log"

@(private)
g_logger: log.Logger

set_logger :: proc(logger: log.Logger) {
	g_logger = logger
}

log_debugf :: proc(fmt_str: string, args: ..any, location := #caller_location) {
	loggerf(.Debug, fmt_str, ..args, location = location)
}
log_infof :: proc(fmt_str: string, args: ..any, location := #caller_location) {
	loggerf(.Info, fmt_str, ..args, location = location)
}
log_warnf :: proc(fmt_str: string, args: ..any, location := #caller_location) {
	loggerf(.Warning, fmt_str, ..args, location = location)
}
log_errorf :: proc(fmt_str: string, args: ..any, location := #caller_location) {
	loggerf(.Error, fmt_str, ..args, location = location)
}
log_fatalf :: proc(fmt_str: string, args: ..any, location := #caller_location) {
	loggerf(.Fatal, fmt_str, ..args, location = location)
}

log_log_debug :: proc(args: ..any, sep := " ", location := #caller_location) {
	logger(.Debug, ..args, sep = sep, location = location)
}
log_info :: proc(args: ..any, sep := " ", location := #caller_location) {
	logger(.Info, ..args, sep = sep, location = location)
}
log_warn :: proc(args: ..any, sep := " ", location := #caller_location) {
	logger(.Warning, ..args, sep = sep, location = location)
}
log_error :: proc(args: ..any, sep := " ", location := #caller_location) {
	logger(.Error, ..args, sep = sep, location = location)
}
log_fatal :: proc(args: ..any, sep := " ", location := #caller_location) {
	logger(.Fatal, ..args, sep = sep, location = location)
}

LOG_BUFFER_SIZE :: 4096

logger :: proc(level: log.Level, args: ..any, sep := " ", location := #caller_location) {
	logger := g_logger
	if logger.procedure == nil || logger.procedure == log.nil_logger_proc {
		return
	}
	if level < logger.lowest_level {
		return
	}

	buf: [LOG_BUFFER_SIZE]byte
	formatted := fmt.bprint(buf[:], ..args, sep = sep)
	logger.procedure(logger.data, level, string(formatted), logger.options, location)
}

loggerf :: proc(level: log.Level, fmt_str: string, args: ..any, location := #caller_location) {
	logger := g_logger
	if logger.procedure == nil || logger.procedure == log.nil_logger_proc {
		return
	}

	if level < logger.lowest_level {
		return
	}

	buf: [LOG_BUFFER_SIZE]byte
	formatted := fmt.bprintf(buf[:], fmt_str, ..args)
	logger.procedure(logger.data, level, string(formatted), logger.options, location)
}
