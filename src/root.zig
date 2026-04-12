//! A small library for writing lexers.

const std = @import("std");

/// A token position
const TokenPos = struct {
    line_num: u64,
    line_pos: u64,
};

/// Generic TokenKind type which contains a type based upon an enum, a matcher,
/// and a handler. TokenType should be an enum of token types.
pub fn TokenKind(comptime TokenType: type) type {
    comptime {
        if (@typeInfo(TokenType) != .@"enum") {
            @compileError("Kind must be an enum, got: " ++ @typeName(TokenType));
        }
    }

    return struct {
        token_type: TokenType,
        token_matcher: *const fn (lexer: *Lexer(TokenType)) bool,
        token_handler: *const fn (lexer: *Lexer(TokenType)) void,
    };
}

/// Helper method for generating a TokenKind which matches against a single character `char` and has a handler which just advances the lexer.
pub fn token_kind_single_ignore(comptime TokenType: type, char: u8) TokenKind(TokenType) {
    return TokenKind(TokenType){
        .token_type = undefined,
        .token_matcher = struct {
            fn matcher(lexer: *Lexer(TokenType)) bool {
                if (lexer.source.ptr[lexer.current_pos] == char) return true;
                return false;
            }
        }.matcher,
        .token_handler = struct {
            fn handler(lexer: *Lexer(TokenType)) void {
                _ = lexer.advance();
            }
        }.handler,
    };
}

/// Helper method for generating a TokenKind which merely matches and handles a single character.
/// TokenType is the enum for the Token, token_type is the specific value in the enum,
/// char is the character to match against, this will also be the value used for the token,
/// increment_line is whether `lexer.line_num` should be incremented when handling the token.
pub fn token_kind_single(comptime TokenType: type, token_type: TokenType, char: u8, increment_line: bool) TokenKind(TokenType) {
    return TokenKind(TokenType){
        .token_type = token_type,
        .token_matcher = struct {
            fn matcher(lexer: *Lexer(TokenType)) bool {
                if (lexer.source.ptr[lexer.current_pos] == char) return true;
                return false;
            }
        }.matcher,
        .token_handler = struct {
            fn handler(lexer: *Lexer(TokenType)) void {
                const consumed_char = lexer.advance();
                lexer.add_token(token_type, &[1]u8{consumed_char});
                if (increment_line) lexer.line_num += 1;
            }
        }.handler,
    };
}

/// Lexer Token.
pub fn Token(comptime TokenType: type) type {
    return struct {
        kind: TokenType,
        value: []const u8,
        pos: TokenPos,
    };
}

/// A lexer which iterates on a piece of source code, matching and handling tokens as it goes.
pub fn Lexer(comptime TokenType: type) type {
    comptime {
        if (@typeInfo(TokenType) != .@"enum") {
            @compileError("Kind must be an enum, got: " ++ @typeName(TokenType));
        }
    }

    return struct {
        /// Allocator for storing tokens.
        allocator: std.mem.Allocator,
        /// Source code input.
        source: []const u8,
        /// List of tokens.
        token_list: std.ArrayList(Token(TokenType)),
        /// Start position of current token.
        start_pos: u64,
        /// Current position of lexer.
        current_pos: u64,
        /// Current line number.
        line_num: u64,

        /// Initialise a lexer with an allocator and source code.
        pub fn init(allocator: std.mem.Allocator, source: []const u8) Lexer(TokenType) {
            return Lexer(TokenType){
                .allocator = allocator,
                .source = source,
                .token_list = std.ArrayList(Token(TokenType)).initCapacity(allocator, 32) catch {
                    @panic("Allocation failed!");
                },
                .start_pos = 0,
                .current_pos = 0,
                .line_num = 0,
            };
        }

        /// De-initialise lexer
        pub fn deinit(lexer: *Lexer(TokenType)) void {
            lexer.token_list.deinit(lexer.allocator);
        }

        /// Scan the source code until the end, matching against the tokens in `token_kind_list` and calling the defined handlers when a match is found.
        /// `eof_token` will be appended to the lexer's `token_list`.
        pub fn scan_source(lexer: *Lexer(TokenType), token_kind_list: []const TokenKind(TokenType), eof_token: TokenType) void {
            while (!lexer.at_end()) {
                lexer.start_pos = lexer.current_pos;
                var found_token = false;
                for (token_kind_list) |token_kind| {
                    if (token_kind.token_matcher(lexer)) {
                        found_token = true;
                        token_kind.token_handler(lexer);
                    }
                }
                if (!found_token) {
                    std.debug.print("Lexer error line: {} pos: {} char: {c} \n", .{ lexer.line_num, lexer.current_pos, lexer.source.ptr[lexer.current_pos] });
                }
            }

            lexer.add_token(eof_token, "EOF");
        }

        /// Whether the lexer is currently at the end of the source code.
        pub fn at_end(lexer: *Lexer(TokenType)) bool {
            return lexer.current_pos >= lexer.source.len;
        }

        /// Peek at the token at the current position without consuming it.
        pub fn peek(lexer: *Lexer(TokenType)) ?u8 {
            if (lexer.at_end()) return null;

            return lexer.source.ptr[lexer.current_pos];
        }

        /// Consume the token at the current position, returning its value and moving the current position forward one character.
        pub fn advance(lexer: *Lexer(TokenType)) u8 {
            const current_char = lexer.source.ptr[lexer.current_pos];
            lexer.current_pos += 1;
            return current_char;
        }

        /// Append a token of type `token_type` with value `value` to the lexer's `token_list`
        pub fn add_token(lexer: *Lexer(TokenType), token_type: TokenType, value: []const u8) void {
            lexer.token_list.append(lexer.allocator, Token(TokenType){
                .kind = token_type,
                .value = value,
                .pos = TokenPos{
                    .line_num = lexer.line_num,
                    .line_pos = 0,
                },
            }) catch {};
        }
    };
}
