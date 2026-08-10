/*
 *   Copyright (c) MediaTek USA Inc., 2026
 *
 *   This program is free software;  you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation; either version 2 of the License, or (at
 *   your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful, but
 *   WITHOUT ANY WARRANTY;  without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *   General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with this program;  if not, see
 *   <http://www.gnu.org/licenses/>.
 */

#pragma once

#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <stdexcept>

/*
 * BinarySerializer.hpp
 *
 * Helper functions for binary serialization of LCOV data structures.
 *
 * Integers go on the wire little-endian, encoded and decoded one byte at a
 * time.  Do not replace this with <endian.h>'s htole32()/le32toh():  that
 * header is glibc's, so it is not there on macOS, on the BSDs, or under MSVC,
 * and this library is expected to build in all of those places.  The shift and
 * mask form needs no such header and no endianness test - and it costs
 * nothing, because both gcc and clang recognize the pattern and emit the same
 * single load or store (plus a byte swap on a big-endian target) that the
 * macros would have.
 */

namespace lcov_binary {

// ============================================================================
// Binary Writer
// ============================================================================

class BinaryWriter {
public:
    BinaryWriter() { buf_.reserve(4096); }

    void write_u8(uint8_t val) {
        buf_.push_back(val);
    }

    void write_u32(uint32_t val) {
        const uint8_t le[4] = { static_cast<uint8_t>(val),
                                static_cast<uint8_t>(val >> 8),
                                static_cast<uint8_t>(val >> 16),
                                static_cast<uint8_t>(val >> 24) };
        buf_.insert(buf_.end(), le, le + 4);
    }

    // the cast is the whole of it:  the bit pattern is what goes on the wire,
    //   and read_i32() casts it back
    void write_i32(int32_t val) {
        write_u32(static_cast<uint32_t>(val));
    }

    void write_u64(uint64_t val) {
        const uint8_t le[8] = { static_cast<uint8_t>(val),
                                static_cast<uint8_t>(val >> 8),
                                static_cast<uint8_t>(val >> 16),
                                static_cast<uint8_t>(val >> 24),
                                static_cast<uint8_t>(val >> 32),
                                static_cast<uint8_t>(val >> 40),
                                static_cast<uint8_t>(val >> 48),
                                static_cast<uint8_t>(val >> 56) };
        buf_.insert(buf_.end(), le, le + 8);
    }

    void write_i64(int64_t val) {
        write_u64(static_cast<uint64_t>(val));
    }

    void write_string(const std::string& s) {
        write_u32(static_cast<uint32_t>(s.size()));
        buf_.insert(buf_.end(), s.begin(), s.end());
    }

    void write_bytes(const void* data, size_t len) {
        const uint8_t* p = static_cast<const uint8_t*>(data);
        buf_.insert(buf_.end(), p, p + len);
    }

    const std::vector<uint8_t>& data() const { return buf_; }
    std::vector<uint8_t>&& take() { return std::move(buf_); }

    void reserve(size_t n) { buf_.reserve(n); }
    size_t size() const { return buf_.size(); }

private:
    std::vector<uint8_t> buf_;
};

// ============================================================================
// Binary Reader
// ============================================================================

class BinaryReader {
public:
    BinaryReader(const uint8_t* data, size_t len)
        : ptr_(data), end_(data + len) {}

    uint8_t read_u8() {
        require(1);
        return *ptr_++;
    }

    uint32_t read_u32() {
        require(4);
        const uint32_t val = static_cast<uint32_t>(ptr_[0]) |
                             (static_cast<uint32_t>(ptr_[1]) << 8) |
                             (static_cast<uint32_t>(ptr_[2]) << 16) |
                             (static_cast<uint32_t>(ptr_[3]) << 24);
        ptr_ += 4;
        return val;
    }

    int32_t read_i32() {
        return static_cast<int32_t>(read_u32());
    }

    uint64_t read_u64() {
        require(8);
        const uint64_t val = static_cast<uint64_t>(ptr_[0]) |
                             (static_cast<uint64_t>(ptr_[1]) << 8) |
                             (static_cast<uint64_t>(ptr_[2]) << 16) |
                             (static_cast<uint64_t>(ptr_[3]) << 24) |
                             (static_cast<uint64_t>(ptr_[4]) << 32) |
                             (static_cast<uint64_t>(ptr_[5]) << 40) |
                             (static_cast<uint64_t>(ptr_[6]) << 48) |
                             (static_cast<uint64_t>(ptr_[7]) << 56);
        ptr_ += 8;
        return val;
    }

    int64_t read_i64() {
        return static_cast<int64_t>(read_u64());
    }

    std::string read_string() {
        uint32_t len = read_u32();
        require(len);
        std::string s(reinterpret_cast<const char*>(ptr_), len);
        ptr_ += len;
        return s;
    }

    void read_bytes(void* dest, size_t len) {
        require(len);
        std::memcpy(dest, ptr_, len);
        ptr_ += len;
    }

    void verify_magic(const char* expected) {
        char magic[4];
        read_bytes(magic, 4);
        if (std::memcmp(magic, expected, 4) != 0) {
            throw std::runtime_error("Invalid magic number");
        }
    }

    size_t bytes_remaining() const { return end_ - ptr_; }
    bool at_end() const { return ptr_ >= end_; }

private:
    // Every read goes through here.  Note the form of the test:  'n' is
    //   generally a length read out of the stream, and the stream may well be
    //   a payload this build did not write, so 'ptr_ + n > end_' is not
    //   good enough - forming a pointer past the end of the buffer is
    //   undefined behaviour, and the sum wraps for a large enough 'n'.
    //   Comparing the space that is left never leaves the object.
    void require(size_t n) const {
        if (static_cast<size_t>(end_ - ptr_) < n)
            throw std::runtime_error("Buffer underrun");
    }

    const uint8_t* ptr_;
    const uint8_t* end_;
};

} // namespace lcov_binary
