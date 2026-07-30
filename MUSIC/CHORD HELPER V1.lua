-- @description ReaHarmonizer V9.8 (Fixed MIDI_SetNote Argument Counts)
-- @version 9.8
-- @requires REAPER 6.0+

local EXT_SECTION = "ReaHarmonizer_Config"
local instance_key = "ReaHarmonizer_Running_Instance"
local unique_id_key = "ReaHarmonizer_Instance_UUID"

local my_uuid = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
reaper.SetExtState(EXT_SECTION, unique_id_key, my_uuid, false)
reaper.SetExtState(EXT_SECTION, instance_key, "1", false)

local function cleanup_instance()
  if reaper.GetExtState(EXT_SECTION, unique_id_key) == my_uuid then
    reaper.SetExtState(EXT_SECTION, instance_key, "0", false)
  end
end

local note_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}

local SCALES = {
  ["None"]              = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11},
  ["Major (Ionian)"]    = {0, 2, 4, 5, 7, 9, 11},
  ["Natural Minor"]     = {0, 2, 3, 5, 7, 8, 10},
  ["Harmonic Minor"]    = {0, 2, 3, 5, 7, 8, 11},
  ["Melodic Minor"]     = {0, 2, 3, 5, 7, 9, 11},
  ["Dorian"]            = {0, 2, 3, 5, 7, 9, 10},
  ["Mixolydian"]        = {0, 2, 4, 5, 7, 9, 10},
  ["Pentatonic Major"]  = {0, 2, 4, 7, 9},
  ["Pentatonic Minor"]  = {0, 3, 5, 7, 10},
  ["Chromatic"]         = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11}
}

local SCALE_NAMES = {
  "None", "Major (Ionian)", "Natural Minor", "Harmonic Minor", "Melodic Minor",
  "Dorian", "Mixolydian", "Pentatonic Major", "Pentatonic Minor", "Chromatic"
}

local SCALE_FACTOR_OPTS = {0.8, 1.0, 1.2, 1.5, 1.8, 2.0}
local SCALE_FACTOR_LABELS = {"80%", "100% (Default)", "120%", "150%", "180%", "200%"}

local COLOR_OPTS = {"Default / Unchanged", "Red", "Green", "Blue", "Yellow", "Cyan", "Magenta", "Orange", "Purple"}

local base_chords = {
  { name = "Major", category = "Triads", intervals = {0, 4, 7} },
  { name = "Minor", category = "Triads", intervals = {0, 3, 7} },
  { name = "Dim",   category = "Triads", intervals = {0, 3, 6} },
  { name = "Aug",   category = "Triads", intervals = {0, 4, 8} },
  { name = "Maj7",  category = "7ths",   intervals = {0, 4, 7, 11} },
  { name = "Min7",  category = "7ths",   intervals = {0, 3, 7, 10} },
  { name = "Dom7",  category = "7ths",   intervals = {0, 4, 7, 10} },
  { name = "Sus4",  category = "Extended/Sus", intervals = {0, 5, 7} }
}

local cfg_default_scale_idx = 1
local cfg_default_lock_state = false
local cfg_remember_chords = false
local cfg_stack_mode = 1
local cfg_auto_lock_detected = true
local cfg_ui_scale_idx = 2
local cfg_run_speed_ms = 800
local cfg_bass_enabled_default = false
local cfg_chord_color_idx = 1
local cfg_bass_color_idx = 1

local selected_notes = {}
local slot_chords = {}
local slot_octaves = {} 
local active_slot_idx = 1
local suggested_chords = {}
local top_note_chords = {}
local octave_offset = 0
local last_selected_count = -1
local last_auditioned_id = ""

local freeze_selection = false
local clear_flash_timer = 0
local clear_notice_timer = 50
local clear_notice_text = "✓ PLEASE SELECT NOTES"

local placement_octave_shift = 0

local active_tab = 1
local detected_keys = {}
local focused_key_idx = 1

local mouse_was_down = false
local current_scale_factor = 1.0
local active_font_size = -1

local current_root_idx = 1
local current_scale_idx = 1
local scale_lock_active = false

local last_w, last_h = 0, 0

local Theme = {
  bg          = {0.11, 0.12, 0.14},
  panel       = {0.15, 0.16, 0.19},
  card        = {0.18, 0.20, 0.24},
  card_hover  = {0.22, 0.25, 0.30},
  card_active = {0.16, 0.44, 0.38},
  disabled    = {0.13, 0.14, 0.16},
  accent      = {0.24, 0.52, 0.88},
  accent_sec  = {0.88, 0.45, 0.24},
  text        = {0.92, 0.93, 0.95},
  text_dim    = {0.50, 0.53, 0.58},
  text_sub    = {0.70, 0.74, 0.80},
  border      = {0.24, 0.26, 0.30},
  lock_on     = {0.18, 0.52, 0.32},
  lock_off    = {0.52, 0.22, 0.22},
  flash_bg    = {0.85, 0.25, 0.20}
}

function save_settings()
  reaper.SetExtState(EXT_SECTION, "default_scale_idx", tostring(cfg_default_scale_idx), true)
  reaper.SetExtState(EXT_SECTION, "default_lock_state", cfg_default_lock_state and "1" or "0", true)
  reaper.SetExtState(EXT_SECTION, "remember_chords", cfg_remember_chords and "1" or "0", true)
  reaper.SetExtState(EXT_SECTION, "stack_mode", tostring(cfg_stack_mode), true)
  reaper.SetExtState(EXT_SECTION, "auto_lock_detected", cfg_auto_lock_detected and "1" or "0", true)
  reaper.SetExtState(EXT_SECTION, "ui_scale_idx", tostring(cfg_ui_scale_idx), true)
  reaper.SetExtState(EXT_SECTION, "run_speed_ms", tostring(cfg_run_speed_ms), true)
  reaper.SetExtState(EXT_SECTION, "bass_enabled_default", cfg_bass_enabled_default and "1" or "0", true)
  reaper.SetExtState(EXT_SECTION, "chord_color_idx", tostring(cfg_chord_color_idx), true)
  reaper.SetExtState(EXT_SECTION, "bass_color_idx", tostring(cfg_bass_color_idx), true)
end

function load_settings()
  if reaper.HasExtState(EXT_SECTION, "default_scale_idx") then
    cfg_default_scale_idx = tonumber(reaper.GetExtState(EXT_SECTION, "default_scale_idx")) or 1
  end
  if reaper.HasExtState(EXT_SECTION, "default_lock_state") then
    cfg_default_lock_state = (reaper.GetExtState(EXT_SECTION, "default_lock_state") == "1")
  end
  if reaper.HasExtState(EXT_SECTION, "remember_chords") then
    cfg_remember_chords = (reaper.GetExtState(EXT_SECTION, "remember_chords") == "1")
  end
  if reaper.HasExtState(EXT_SECTION, "stack_mode") then
    cfg_stack_mode = tonumber(reaper.GetExtState(EXT_SECTION, "stack_mode")) or 1
  end
  if reaper.HasExtState(EXT_SECTION, "auto_lock_detected") then
    cfg_auto_lock_detected = (reaper.GetExtState(EXT_SECTION, "auto_lock_detected") == "1")
  end
  if reaper.HasExtState(EXT_SECTION, "ui_scale_idx") then
    cfg_ui_scale_idx = tonumber(reaper.GetExtState(EXT_SECTION, "ui_scale_idx")) or 2
  end
  if reaper.HasExtState(EXT_SECTION, "run_speed_ms") then
    cfg_run_speed_ms = tonumber(reaper.GetExtState(EXT_SECTION, "run_speed_ms")) or 800
  end
  if reaper.HasExtState(EXT_SECTION, "bass_enabled_default") then
    cfg_bass_enabled_default = (reaper.GetExtState(EXT_SECTION, "bass_enabled_default") == "1")
  end
  if reaper.HasExtState(EXT_SECTION, "chord_color_idx") then
    cfg_chord_color_idx = tonumber(reaper.GetExtState(EXT_SECTION, "chord_color_idx")) or 1
  end
  if reaper.HasExtState(EXT_SECTION, "bass_color_idx") then
    cfg_bass_color_idx = tonumber(reaper.GetExtState(EXT_SECTION, "bass_color_idx")) or 1
  end

  current_scale_idx = cfg_default_scale_idx
  scale_lock_active = cfg_default_lock_state
  current_scale_factor = SCALE_FACTOR_OPTS[cfg_ui_scale_idx] or 1.0
end

function reset_stored_chords_full()
  slot_chords = {}
  slot_octaves = {}
  selected_notes = {}
  last_selected_count = -1
  freeze_selection = false
  last_auditioned_id = ""
  clear_flash_timer = 15
  clear_notice_timer = 40
  clear_notice_text = "✓ CLEARED PROGRESSION"
end

function set_color(c, alpha)
  gfx.r = c[1]
  gfx.g = c[2]
  gfx.b = c[3]
  gfx.a = alpha or 1.0
end

function S(val)
  return math.floor(val * current_scale_factor + 0.5)
end

function update_font()
  local font_size = math.max(10, math.floor(13 * current_scale_factor))
  if font_size ~= active_font_size then
    gfx.setfont(1, "Arial", font_size)
    active_font_size = font_size
  end
end

function midi_note_to_string(pitch)
  if pitch < 0 or pitch > 127 then return "---" end
  local name = note_names[(pitch % 12) + 1]
  local octave = math.floor(pitch / 12) - 1
  return name .. octave
end

function get_scale_notes(root_idx, scale_name)
  local intervals = SCALES[scale_name] or SCALES["None"]
  local notes = {}
  local root_val = root_idx - 1
  for _, interval in ipairs(intervals) do
    notes[(root_val + interval) % 12] = true
  end
  return notes
end

function apply_inversion(intervals, inv)
  local result = {table.unpack(intervals)}
  for i = 1, inv do
    if #result > 0 then
      local first = table.remove(result, 1)
      table.insert(result, first + 12)
    end
  end
  return result
end

function is_chord_in_scale(chord_pitches, root_idx, scale_name)
  local r = root_idx or current_root_idx
  local s = scale_name or SCALE_NAMES[current_scale_idx]
  if s == "None" then return true end
  
  local scale_map = get_scale_notes(r, s)
  for _, p in ipairs(chord_pitches) do
    if not scale_map[p % 12] then
      return false
    end
  end
  return true
end

function get_chord_shifted_label(chord, slot_idx)
  if not chord then return "[ Select ]" end
  local slot_oct = (slot_octaves[slot_idx] or 0)
  local root_p = chord.pitches[1] + (slot_oct * 12)
  if root_p < 0 or root_p > 127 then return chord.base_name end
  
  local extension = chord.base_name
  if chord.inversion > 0 then
    extension = extension .. " (" .. chord.inversion .. "i)"
  end

  return midi_note_to_string(root_p) .. " " .. extension
end

function sync_to_detected_key()
  if #detected_keys > 0 then
    local target = detected_keys[focused_key_idx] or detected_keys[1]
    current_root_idx = target.root_idx
    for s_idx, s_name in ipairs(SCALE_NAMES) do
      if s_name == target.scale_name then
        current_scale_idx = s_idx
        break
      end
    end
    scale_lock_active = true
    generate_all_chords(active_slot_idx)
    validate_slot_chords()
    clear_notice_timer = 40
    clear_notice_text = "✓ SYNCED TO DETECTED: " .. target.root_name .. " " .. target.scale_name
  end
end

function detect_key()
  detected_keys = {}
  if #selected_notes == 0 then return end

  local pitch_counts = {}
  for i = 0, 11 do pitch_counts[i] = 0 end
  for _, note in ipairs(selected_notes) do
    local pc = note.pitch % 12
    pitch_counts[pc] = pitch_counts[pc] + 1
  end

  local total_notes = #selected_notes
  local match_scores = {}

  for root_i = 1, 12 do
    for s_name, intervals in pairs(SCALES) do
      if s_name ~= "Chromatic" and s_name ~= "None" then
        local scale_map = {}
        for _, val in ipairs(intervals) do
          scale_map[(root_i - 1 + val) % 12] = true
        end

        local matched_count = 0
        for pc, count in pairs(pitch_counts) do
          if count > 0 and scale_map[pc] then
            matched_count = matched_count + count
          end
        end

        local confidence = math.floor((matched_count / total_notes) * 100)
        table.insert(match_scores, {
          root_idx = root_i,
          root_name = note_names[root_i],
          scale_name = s_name,
          confidence = confidence
        })
      end
    end
  end

  table.sort(match_scores, function(a, b)
    if a.confidence == b.confidence then
      return a.root_name < b.root_name
    end
    return a.confidence > b.confidence
  end)

  local unique = {}
  for _, item in ipairs(match_scores) do
    if #detected_keys >= 4 then break end
    local key_id = item.root_name .. " " .. item.scale_name
    if not unique[key_id] then
      unique[key_id] = true
      table.insert(detected_keys, item)
    end
  end

  if #detected_keys > 0 then focused_key_idx = 1 end
end

function generate_all_chords(note_index)
  suggested_chords = {}
  top_note_chords = {}
  if not selected_notes[note_index] then return end
  
  local target_pitch = selected_notes[note_index].pitch + (octave_offset * 12)
  local inv_names = {[0] = "Root Pos", [1] = "1st Inv", [2] = "2nd Inv"}
  
  for inv = 0, 2 do
    for def_idx, def in ipairs(base_chords) do
      local inv_intervals = apply_inversion(def.intervals, inv)
      local chord_pitches = {}
      
      for _, interval in ipairs(inv_intervals) do
        table.insert(chord_pitches, target_pitch + interval)
      end
      
      local chord_label = midi_note_to_string(target_pitch) .. " " .. def.name .. (inv == 0 and "" or (" (" .. inv .. "i)"))
      local in_scale = is_chord_in_scale(chord_pitches, current_root_idx, SCALE_NAMES[current_scale_idx])

      table.insert(suggested_chords, {
        label = chord_label,
        pitches = chord_pitches,
        inversion = inv,
        inv_title = inv_names[inv],
        base_name = def.name,
        category = def.category,
        in_scale = in_scale,
        def_idx = def_idx,
        root_pitch = target_pitch
      })
    end
  end

  for def_idx, def in ipairs(base_chords) do
    for inv = 0, 2 do
      local inv_intervals = apply_inversion(def.intervals, inv)
      local max_interval = inv_intervals[#inv_intervals]
      local calculated_root = target_pitch - max_interval
      
      local chord_pitches = {}
      for _, interval in ipairs(inv_intervals) do
        table.insert(chord_pitches, calculated_root + interval)
      end
      
      local chord_label = midi_note_to_string(calculated_root) .. " " .. def.name .. (inv == 0 and "" or (" (" .. inv .. "i)"))
      local in_scale = is_chord_in_scale(chord_pitches, current_root_idx, SCALE_NAMES[current_scale_idx])

      table.insert(top_note_chords, {
        label = chord_label,
        pitches = chord_pitches,
        inversion = inv,
        base_name = def.name,
        category = def.category,
        in_scale = in_scale,
        def_idx = def_idx,
        root_pitch = calculated_root
      })
    end
  end
end

function validate_slot_chords()
  if scale_lock_active and SCALE_NAMES[current_scale_idx] ~= "None" then
    for idx, chord in pairs(slot_chords) do
      if chord and not is_chord_in_scale(chord.pitches, current_root_idx, SCALE_NAMES[current_scale_idx]) then
        slot_chords[idx] = nil
      end
    end
  end
end

function scan_selected_notes()
  if freeze_selection then return end

  local editor = reaper.MIDIEditor_GetActive()
  if not editor then return end
  local take = reaper.MIDIEditor_GetTake(editor)
  if not take then return end

  local temp_notes = {}
  local note_idx = -1
  while true do
    note_idx = reaper.MIDI_EnumSelNotes(take, note_idx)
    if note_idx == -1 then break end
    
    local _, sel, muted, start_ppq, end_ppq, chan, pitch, vel = reaper.MIDI_GetNote(take, note_idx)
    table.insert(temp_notes, {
      take = take,
      idx = note_idx,
      start_ppq = start_ppq,
      end_ppq = end_ppq,
      chan = chan,
      pitch = pitch,
      vel = vel
    })
  end

  if #temp_notes ~= last_selected_count then
    selected_notes = temp_notes
    table.sort(selected_notes, function(a, b) return a.start_ppq < b.start_ppq end)
    last_selected_count = #temp_notes
    
    if not cfg_remember_chords then
      slot_chords = {}
      slot_octaves = {}
    end
    
    if #selected_notes > 0 then
      active_slot_idx = 1
      detect_key()
      generate_all_chords(1)
    end
  end
end

function audition_vst(pitches, channel, velocity, octave_shift_override)
  for p = 0, 127 do
    reaper.StuffMIDIMessage(0, 0x80 + (channel or 0), p, 0)
  end

  local shift = (octave_shift_override or 0) * 12
  for _, p in ipairs(pitches) do
    local shifted = p + shift
    if shifted >= 0 and shifted <= 127 then
      reaper.StuffMIDIMessage(0, 0x90 + (channel or 0), shifted, velocity or 90)
    end
  end
end

function preview_scale_run(root_idx, scale_name)
  local intervals = SCALES[scale_name] or SCALES["Major (Ionian)"]
  local root_val = (root_idx - 1) + 48
  local run_pitches = {}
  for _, interval in ipairs(intervals) do
    table.insert(run_pitches, root_val + interval)
  end
  table.insert(run_pitches, root_val + 12)

  local current_step = 1
  local target_time = reaper.time_precise() + (cfg_run_speed_ms / 1000.0)
  
  local function timed_play()
    local now = reaper.time_precise()
    if now >= target_time then
      if current_step <= #run_pitches then
        if current_step > 1 then
          audition_vst({run_pitches[current_step - 1]}, 0, 0, 0)
        end
        audition_vst({run_pitches[current_step]}, 0, 90, 0)
        current_step = current_step + 1
        target_time = reaper.time_precise() + (cfg_run_speed_ms / 1000.0)
        reaper.defer(timed_play)
      end
    else
      reaper.defer(timed_play)
    end
  end
  timed_play()
end

function get_smart_non_overlapping_bass(chord_pitches, slot_oct)
  local shift = (slot_oct or 0) * 12
  local lowest_chord_pitch = 128
  for _, p in ipairs(chord_pitches) do
    local shifted_p = p + shift
    if shifted_p < lowest_chord_pitch then
      lowest_chord_pitch = shifted_p
    end
  end

  local base_bass = 36 + ((chord_pitches[1] + shift) % 12)
  while base_bass < 24 do base_bass = base_bass + 12 end

  while base_bass + 12 < lowest_chord_pitch do
    base_bass = base_bass + 12
  end

  while base_bass >= lowest_chord_pitch do
    base_bass = base_bass - 12
  end

  if base_bass < 0 then base_bass = 0 end
  return base_bass
end

function get_reaper_color_val(color_idx)
  if color_idx <= 1 then return nil end
  local r, g, b = 0, 0, 0
  if color_idx == 2 then r, g, b = 255, 60, 60
  elseif color_idx == 3 then r, g, b = 60, 220, 60
  elseif color_idx == 4 then r, g, b = 60, 120, 255
  elseif color_idx == 5 then r, g, b = 240, 220, 40
  elseif color_idx == 6 then r, g, b = 40, 220, 220
  elseif color_idx == 7 then r, g, b = 220, 60, 220
  elseif color_idx == 8 then r, g, b = 255, 140, 40
  elseif color_idx == 9 then r, g, b = 160, 60, 255
  end
  return reaper.ColorToNative(r, g, b) | 0x1000000
end

function insert_all_chords()
  if #selected_notes == 0 then return end
  
  reaper.Undo_BeginBlock()
  
  freeze_selection = true
  
  local chord_col = get_reaper_color_val(cfg_chord_color_idx)
  local bass_col = get_reaper_color_val(cfg_bass_color_idx)

  for i, target in ipairs(selected_notes) do
    local chord = slot_chords[i]
    if chord then
      local slot_oct = (slot_octaves[i] or 0)
      local shift = slot_oct * 12
      local base_chord_pitches = {}
      for _, p in ipairs(chord.pitches) do
        local final_p = p + shift
        if final_p >= 0 and final_p <= 127 then
          base_chord_pitches[final_p] = true
        end
      end

      local smart_bass = -1
      if cfg_bass_enabled_default then
        smart_bass = get_smart_non_overlapping_bass(chord.pitches, slot_oct)
      end

      if cfg_stack_mode == 1 then
        reaper.MIDI_DeleteNote(target.take, target.idx)
        for p, _ in pairs(base_chord_pitches) do
          local retval, _, _, _, _, _, _, _, _ = reaper.MIDI_InsertNote(target.take, true, false, target.start_ppq, target.end_ppq, target.chan, p, target.vel, false)
          if chord_col and retval then
            reaper.MIDI_SetNote(target.take, retval, nil, nil, nil, nil, nil, nil, nil, true)
          end
        end
        if cfg_bass_enabled_default and smart_bass >= 0 and smart_bass <= 127 then
          local bass_retval, _, _, _, _, _, _, _, _ = reaper.MIDI_InsertNote(target.take, true, false, target.start_ppq, target.end_ppq, target.chan, smart_bass, target.vel, false)
          if bass_col and bass_retval then
            reaper.MIDI_SetNote(target.take, bass_retval, nil, nil, nil, nil, nil, nil, nil, true)
          end
        end
      else
        local target_pitch = target.pitch
        local chord_min = 128
        local chord_max = -1
        for p, _ in pairs(base_chord_pitches) do
          if p < chord_min then chord_min = p end
          if p > chord_max then chord_max = p end
        end

        local adjusted_shift = 0
        if cfg_stack_mode == 2 then
          if chord_min <= target_pitch then
            local diff = target_pitch - chord_min
            local oct_bumps = math.ceil((diff + 1) / 12)
            oct_bumps = math.min(2, math.max(1, oct_bumps))
            adjusted_shift = oct_bumps * 12
          end
        elseif cfg_stack_mode == 3 then
          if chord_max >= target_pitch then
            local diff = chord_max - target_pitch
            local oct_bumps = math.ceil((diff + 1) / 12)
            oct_bumps = math.min(2, math.max(1, oct_bumps))
            adjusted_shift = - (oct_bumps * 12)
          end
        end

        local existing_pitches_at_time = {}
        local note_idx = -1
        while true do
          note_idx = reaper.MIDI_EnumSelNotes(target.take, note_idx)
          if note_idx == -1 then break end
          local _, _, _, st, en, _, pt, _ = reaper.MIDI_GetNote(target.take, note_idx)
          if not (en <= target.start_ppq or st >= target.end_ppq) then
            existing_pitches_at_time[pt] = true
          end
        end

        for p, _ in pairs(base_chord_pitches) do
          local shifted_chord_pitch = p + adjusted_shift
          if shifted_chord_pitch >= 0 and shifted_chord_pitch <= 127 then
            if not existing_pitches_at_time[shifted_chord_pitch] then
              local retval, _, _, _, _, _, _, _, _ = reaper.MIDI_InsertNote(target.take, true, false, target.start_ppq, target.end_ppq, target.chan, shifted_chord_pitch, target.vel, false)
              if chord_col and retval then
                reaper.MIDI_SetNote(target.take, retval, nil, nil, nil, nil, nil, nil, nil, true)
              end
            end
          end
        end

        if cfg_bass_enabled_default and smart_bass >= 0 and smart_bass <= 127 then
          local shifted_bass_pitch = smart_bass + adjusted_shift
          if shifted_bass_pitch >= 0 and shifted_bass_pitch <= 127 then
            if not existing_pitches_at_time[shifted_bass_pitch] then
              local bass_retval, _, _, _, _, _, _, _, _ = reaper.MIDI_InsertNote(target.take, true, false, target.start_ppq, target.end_ppq, target.chan, shifted_bass_pitch, target.vel, false)
              if bass_col and bass_retval then
                reaper.MIDI_SetNote(target.take, bass_retval, nil, nil, nil, nil, nil, nil, nil, true)
              end
            end
          end
        end
      end
    end
  end
  if #selected_notes > 0 then reaper.MIDI_Sort(selected_notes[1].take) end
  reaper.Undo_EndBlock("Insert Harmonized Chord Progression", -1)
  
  last_selected_count = -1
  scan_selected_notes()
end

function draw_card(x, y, w, h, bg, text, is_active, subtext, is_disabled, custom_border)
  local hover = gfx.mouse_x >= x and gfx.mouse_x <= x + w and gfx.mouse_y >= y and gfx.mouse_y <= y + h
  local mouse_click = hover and (gfx.mouse_cap & 1 == 1) and not mouse_was_down
  local c = bg

  if is_disabled then
    c = Theme.disabled
  elseif is_active then
    c = Theme.card_active
  elseif hover then
    c = Theme.card_hover
  end

  set_color(c)
  gfx.rect(x, y, w, h, 1)

  local b = custom_border or Theme.border
  if is_active then
    set_color({0.3, 0.8, 0.5})
  elseif is_disabled then
    set_color({0.18, 0.19, 0.22})
  else
    set_color(b)
  end
  gfx.rect(x, y, w, h, 0)

  if is_disabled then
    set_color(Theme.text_dim)
  else
    set_color(Theme.text)
  end

  local font_h = gfx.texth

  if subtext then
    gfx.x = x + S(6)
    gfx.y = y + S(3)
    gfx.drawstr(text)
    
    if is_disabled then
      set_color(Theme.text_dim)
    else
      set_color(Theme.text_sub)
    end
    gfx.x = x + S(6)
    gfx.y = y + S(3) + font_h + 1
    gfx.drawstr(subtext)
  else
    local str_w = gfx.measurestr(text)
    gfx.x = x + (w / 2) - (str_w / 2)
    gfx.y = y + (h / 2) - (font_h / 2)
    gfx.drawstr(text)
  end

  return mouse_click and not is_disabled
end

function draw_dropdown(x, y, w, h, label, options, selected_idx)
  local display_text = label .. ": " .. options[selected_idx] .. " v"
  if draw_card(x, y, w, h, Theme.card, display_text, false, nil, false) then
    local menu_str = ""
    for i, opt in ipairs(options) do
      if i == selected_idx then
        menu_str = menu_str .. "!" .. opt .. "|"
      else
        menu_str = menu_str .. opt .. "|"
      end
    end
    gfx.x, gfx.y = x, y + h
    local choice = gfx.showmenu(menu_str)
    if choice > 0 then
      return choice
    end
  end
  return selected_idx
end

function toggle_dock()
  if gfx.dock(-1) > 0 then
    gfx.dock(0)
  else
    gfx.dock(1)
  end
end

function main()
  if reaper.GetExtState(EXT_SECTION, unique_id_key) ~= my_uuid then
    gfx.quit()
    return
  end

  scan_selected_notes()
  update_font()

  if gfx.w ~= last_w or gfx.h ~= last_h then
    last_w, last_h = gfx.w, gfx.h
  end

  set_color(Theme.bg)
  gfx.rect(0, 0, gfx.w, gfx.h, 1)

  local pad_x = S(12)
  local content_w = math.max(S(200), gfx.w - (pad_x * 2))
  local font_h = gfx.texth

  local header_y = S(8)
  local tab_w = S(100)
  if draw_card(pad_x, header_y, tab_w, S(24), Theme.card, "1. MAIN", active_tab == 1, nil, false) then
    active_tab = 1
  end
  if draw_card(pad_x + tab_w + S(4), header_y, tab_w, S(24), Theme.card, "2. KEYS", active_tab == 2, nil, false) then
    active_tab = 2
  end
  if draw_card(pad_x + (tab_w * 2) + S(8), header_y, tab_w, S(24), Theme.card, "3. SET", active_tab == 3, nil, false) then
    active_tab = 3
  end

  if active_tab == 1 or active_tab == 2 then
    local action_btn_w = S(90)
    local action_x = pad_x + (tab_w * 3) + S(14)
    
    if clear_flash_timer > 0 then clear_flash_timer = clear_flash_timer - 1 end
    local clear_bg = (clear_flash_timer > 0) and Theme.flash_bg or Theme.card
    if draw_card(action_x, header_y, action_btn_w, S(24), clear_bg, "CLEAR", false, nil, false) then
      reset_stored_chords_full()
    end

    local store_x = action_x + action_btn_w + S(6)
    local has_stored_content = freeze_selection
    local store_bg = has_stored_content and Theme.card_active or Theme.disabled
    local store_border = has_stored_content and {0.3, 0.8, 0.5} or Theme.border
    
    if draw_card(store_x, header_y, action_btn_w, S(24), store_bg, "STORE", has_stored_content, nil, false, store_border) then
      freeze_selection = not freeze_selection
    end
  end

  local dock_label = (gfx.dock(-1) > 0) and "FLOAT" or "DOCK"
  if draw_card(gfx.w - pad_x - S(50), header_y, S(50), S(24), Theme.card, dock_label, false, nil, false) then
    toggle_dock()
  end

  if clear_notice_timer > 0 then
    clear_notice_timer = clear_notice_timer - 1
    local notice_y = header_y + S(28)
    set_color(Theme.flash_bg, math.min(1.0, clear_notice_timer / 15))
    gfx.rect(pad_x, notice_y, content_w, S(22), 1)
    set_color(Theme.text)
    local str_w = gfx.measurestr(clear_notice_text)
    gfx.x = (gfx.w / 2) - (str_w / 2)
    gfx.y = notice_y + S(3)
    gfx.drawstr(clear_notice_text)
  end

  local top_offset = header_y + S(36)

  if active_tab == 3 then
    set_color(Theme.accent)
    gfx.x, gfx.y = pad_x, top_offset
    gfx.drawstr("REAHARMONIZER GLOBAL SETTINGS")
    set_color(Theme.border)
    gfx.line(pad_x, top_offset + font_h + S(4), gfx.w - pad_x, top_offset + font_h + S(4))

    local set_y = top_offset + font_h + S(16)
    local row_h = font_h + S(14)
    local set_val_w = S(220)

    set_color(Theme.text_sub)
    gfx.x, gfx.y = pad_x, set_y + S(6)
    gfx.drawstr("Default Scale on Launch:")

    local new_def_scale = draw_dropdown(gfx.w - pad_x - set_val_w, set_y, set_val_w, row_h, "Default", SCALE_NAMES, cfg_default_scale_idx)
    if new_def_scale ~= cfg_default_scale_idx then
      cfg_default_scale_idx = new_def_scale
      save_settings()
    end

    set_y = set_y + row_h + S(10)
    set_color(Theme.text_sub)
    gfx.x, gfx.y = pad_x, set_y + S(6)
    gfx.drawstr("Default Scale Lock Mode:")

    local lock_def_text = cfg_default_lock_state and "ON (Restrict Non-Scale Chords)" or "OFF (Allow All Chords)"
    local lock_def_bg = cfg_default_lock_state and Theme.lock_on or Theme.lock_off
    if draw_card(gfx.w - pad_x - set_val_w, set_y, set_val_w, row_h, lock_def_bg, lock_def_text, false, nil, false) then
      cfg_default_lock_state = not cfg_default_lock_state
      save_settings()
    end

    set_y = set_y + row_h + S(10)
    set_color(Theme.text_sub)
    gfx.x, gfx.y = pad_x, set_y + S(6)
    gfx.drawstr("Auto Scale-Lock on Detected Key Selection:")

    local auto_lock_text = cfg_auto_lock_detected and "ENABLED (Auto-Lock Selected Key)" or "DISABLED (Manual Lock Only)"
    local auto_lock_bg = cfg_auto_lock_detected and Theme.lock_on or Theme.card
    if draw_card(gfx.w - pad_x - set_val_w, set_y, set_val_w, row_h, auto_lock_bg, auto_lock_text, false, nil, false) then
      cfg_auto_lock_detected = not cfg_auto_lock_detected
      save_settings()
    end

    set_y = set_y + row_h + S(10)
    set_color(Theme.text_sub)
    gfx.x, gfx.y = pad_x, set_y + S(6)
    gfx.drawstr("Remember Chords Across Selections:")

    local rem_text = cfg_remember_chords and "ENABLED (Persistent Assignments)" or "DISABLED (Reset on New Note)"
    local rem_bg = cfg_remember_chords and Theme.card_active or Theme.card
    if draw_card(gfx.w - pad_x - set_val_w, set_y, set_val_w, row_h, rem_bg, rem_text, false, nil, false) then
      cfg_remember_chords = not cfg_remember_chords
      save_settings()
    end

    set_y = set_y + row_h + S(10)
    set_color(Theme.text_sub)
    gfx.x, gfx.y = pad_x, set_y + S(6)
    gfx.drawstr("Add Bass Note as Default:")

    local bass_text = cfg_bass_enabled_default and "ENABLED (Add Bass by Default)" or "DISABLED (No Bass by Default)"
    local bass_bg = cfg_bass_enabled_default and Theme.lock_on or Theme.card
    if draw_card(gfx.w - pad_x - set_val_w, set_y, set_val_w, row_h, bass_bg, bass_text, false, nil, false) then
      cfg_bass_enabled_default = not cfg_bass_enabled_default
      save_settings()
    end

    set_y = set_y + row_h + S(10)
    set_color(Theme.text_sub)
    gfx.x, gfx.y = pad_x, set_y + S(6)
    gfx.drawstr("Entered Chords MIDI Color:")

    local new_chord_col = draw_dropdown(gfx.w - pad_x - set_val_w, set_y, set_val_w, row_h, "Color", COLOR_OPTS, cfg_chord_color_idx)
    if new_chord_col ~= cfg_chord_color_idx then
      cfg_chord_color_idx = new_chord_col
      save_settings()
    end

    set_y = set_y + row_h + S(10)
    set_color(Theme.text_sub)
    gfx.x, gfx.y = pad_x, set_y + S(6)
    gfx.drawstr("Entered Bass Note MIDI Color:")

    local new_bass_col = draw_dropdown(gfx.w - pad_x - set_val_w, set_y, set_val_w, row_h, "Color", COLOR_OPTS, cfg_bass_color_idx)
    if new_bass_col ~= cfg_bass_color_idx then
      cfg_bass_color_idx = new_bass_col
      save_settings()
    end

    set_y = set_y + row_h + S(10)
    set_color(Theme.text_sub)
    gfx.x, gfx.y = pad_x, set_y + S(6)
    gfx.drawstr("Note Insertion Strategy (Stacking):")

    local stack_options = {"1. Replace Original Note", "2. Smart Stack ABOVE Melody", "3. Smart Stack BELOW Melody"}
    local new_stack = draw_dropdown(gfx.w - pad_x - set_val_w, set_y, set_val_w, row_h, "Strategy", stack_options, cfg_stack_mode)
    if new_stack ~= cfg_stack_mode then
      cfg_stack_mode = new_stack
      save_settings()
    end

    set_y = set_y + row_h + S(10)
    set_color(Theme.text_sub)
    gfx.x, gfx.y = pad_x, set_y + S(6)
    gfx.drawstr("Preview Scale Run Speed (ms per note):")

    local speeds = {200, 400, 600, 800, 1000, 1200}
    local speed_labels = {"200ms", "400ms", "600ms", "800ms (Practice)", "1000ms (1 sec)", "1200ms (Very Slow)"}
    local cur_speed_idx = 4
    for s_i, spd in ipairs(speeds) do if spd == cfg_run_speed_ms then cur_speed_idx = s_i break end end
    local new_speed_idx = draw_dropdown(gfx.w - pad_x - set_val_w, set_y, set_val_w, row_h, "Run Speed", speed_labels, cur_speed_idx)
    if new_speed_idx ~= cur_speed_idx then
      cfg_run_speed_ms = speeds[new_speed_idx]
      save_settings()
    end

    set_y = set_y + row_h + S(10)
    set_color(Theme.text_sub)
    gfx.x, gfx.y = pad_x, set_y + S(6)
    gfx.drawstr("Interface Scaling Factor (Default):")

    local new_ui_scale = draw_dropdown(gfx.w - pad_x - set_val_w, set_y, set_val_w, row_h, "UI Scale", SCALE_FACTOR_LABELS, cfg_ui_scale_idx)
    if new_ui_scale ~= cfg_ui_scale_idx then
      cfg_ui_scale_idx = new_ui_scale
      current_scale_factor = SCALE_FACTOR_OPTS[cfg_ui_scale_idx] or 1.0
      active_font_size = -1
      save_settings()
    end

    set_y = set_y + row_h + S(24)
    set_color(Theme.border)
    gfx.line(pad_x, set_y, gfx.w - pad_x, set_y)
    set_y = set_y + S(14)

    set_color(Theme.accent_sec)
    gfx.x, gfx.y = pad_x, set_y
    gfx.drawstr("QUICK ACTION")
    
    set_y = set_y + font_h + S(8)
    local reset_btn_w = S(320)
    if draw_card(pad_x, set_y, reset_btn_w, row_h + S(4), Theme.lock_off, "RESET: CLEAR CHORDS, SCALE = NONE, LOCK = OFF", false, nil, false) then
      reset_stored_chords_full()
    end

  elseif #selected_notes == 0 then
    set_color(Theme.panel)
    gfx.rect(pad_x, top_offset, content_w, S(150), 1)
    set_color(Theme.border)
    gfx.rect(pad_x, top_offset, content_w, S(150), 0)

    set_color(Theme.accent)
    gfx.x, gfx.y = pad_x + S(12), top_offset + S(15)
    gfx.drawstr("ReaHarmonizer V9.8")
    
    set_color(Theme.text_sub)
    gfx.x, gfx.y = pad_x + S(12), top_offset + S(15) + font_h + S(10)
    gfx.drawstr("1. Select melody notes in REAPER's MIDI Editor.")
    gfx.x, gfx.y = pad_x + S(12), top_offset + S(15) + (font_h * 2) + S(16)
    gfx.drawstr("2. Click 'STORE' to lock current selection.")
    gfx.x, gfx.y = pad_x + S(12), top_offset + S(15) + (font_h * 3) + S(22)
    gfx.drawstr("3. Use slot card buttons to assign chords and build progression.")
  else

    local num_slots = math.max(#selected_notes, 1)
    local slot_gap = S(6)
    local slot_w = math.max(S(75), math.floor((content_w - (slot_gap * (num_slots - 1))) / num_slots))

    set_color(Theme.text_dim)
    gfx.x, gfx.y = pad_x, top_offset
    gfx.drawstr("BEAT NOTES PREVIEW")

    for i, note in ipairs(selected_notes) do
      local sx = pad_x + (i - 1) * (slot_w + slot_gap)
      local sy = top_offset + font_h + S(4)
      local target_pitch = note.pitch + (placement_octave_shift * 12)
      local pitch_str = midi_note_to_string(target_pitch)
      local label = "B" .. i .. " • " .. pitch_str
      
      if draw_card(sx, sy, slot_w, font_h + S(10), Theme.card, label, false, nil, false) then
        active_slot_idx = i
        generate_all_chords(active_slot_idx)
        
        local trigger_id = "NOTE_" .. i
        if last_auditioned_id ~= trigger_id then
          audition_vst({note.pitch}, note.chan, note.vel, placement_octave_shift)
          last_auditioned_id = trigger_id
        end
      end
    end

    local slots_y = top_offset + font_h + S(14) + font_h + S(14)
    set_color(Theme.text_dim)
    gfx.x, gfx.y = pad_x, slots_y
    gfx.drawstr("CHORDS SELECTED PREVIEW (WITH OCTAVE)")

    for i, note in ipairs(selected_notes) do
      local sx = pad_x + (i - 1) * (slot_w + slot_gap)
      local sy = slots_y + font_h + S(4)
      local card_h = (font_h * 2) + S(12)
      local assigned = get_chord_shifted_label(slot_chords[i], i)
      local header = "Slot " .. i

      if draw_card(sx, sy, slot_w, card_h, Theme.panel, header, i == active_slot_idx, assigned, false) then
        active_slot_idx = i
        generate_all_chords(active_slot_idx)
        
        local trigger_id = "SLOT_CHORD_" .. i
        if last_auditioned_id ~= trigger_id then
          if slot_chords[i] then
            local slot_oct = slot_octaves[i] or 0
            local pitches_to_play = {table.unpack(slot_chords[i].pitches)}
            if cfg_bass_enabled_default then
              table.insert(pitches_to_play, get_smart_non_overlapping_bass(slot_chords[i].pitches, slot_oct))
            end
            audition_vst(pitches_to_play, note.chan, note.vel, slot_oct)
          else
            audition_vst({note.pitch}, note.chan, note.vel, placement_octave_shift)
          end
          last_auditioned_id = trigger_id
        end
      end

      local cur_slot_oct = slot_octaves[i] or 0
      local arrow_w = S(16)
      local arrow_h = math.floor((card_h - S(10)) / 2)
      local arrow_x = sx + slot_w - arrow_w - S(4)
      local up_y = sy + S(2)
      local down_y = sy + card_h - arrow_h - S(2)
      local oct_text_y = sy + math.floor((card_h - font_h) / 2) + S(2)

      set_color(Theme.accent)
      gfx.x = arrow_x - S(22)
      gfx.y = oct_text_y
      gfx.drawstr((cur_slot_oct > 0 and "+" or "") .. cur_slot_oct)

      if draw_card(arrow_x, up_y, arrow_w, arrow_h, Theme.card, "^", false, nil, false) then
        slot_octaves[i] = math.min(3, cur_slot_oct + 1)
        if slot_chords[i] then
          audition_vst(slot_chords[i].pitches, note.chan, note.vel, slot_octaves[i])
        end
      end

      if draw_card(arrow_x, down_y, arrow_w, arrow_h, Theme.card, "v", false, nil, false) then
        slot_octaves[i] = math.max(-3, cur_slot_oct - 1)
        if slot_chords[i] then
          audition_vst(slot_chords[i].pitches, note.chan, note.vel, slot_octaves[i])
        end
      end
    end

    local common_bottom_y = slots_y + font_h + S(4) + (font_h * 2) + S(20)

    if active_tab == 2 then
      set_color(Theme.accent_sec)
      gfx.x, gfx.y = pad_x, common_bottom_y
      gfx.drawstr("DETECTED KEY CANDIDATES")
      set_color(Theme.border)
      gfx.line(pad_x, common_bottom_y + font_h + S(4), gfx.w - pad_x, common_bottom_y + font_h + S(4))

      local key_card_y = common_bottom_y + font_h + S(8)
      local num_keys = math.min(4, #detected_keys)
      local key_card_w = math.floor((content_w - (S(6) * (num_keys - 1))) / math.max(1, num_keys))

      for i = 1, num_keys do
        local key = detected_keys[i]
        local kx = pad_x + (i - 1) * (key_card_w + S(6))
        local title = key.root_name .. " " .. key.scale_name
        local sub = key.confidence .. "% Match"
        local is_focused = (focused_key_idx == i)

        if draw_card(kx, key_card_y, key_card_w, (font_h * 2) + S(16), Theme.panel, title, is_focused, sub, false) then
          focused_key_idx = i
          current_root_idx = key.root_idx
          for s_idx, s_name in ipairs(SCALE_NAMES) do
            if s_name == key.scale_name then current_scale_idx = s_idx break end
          end
          if cfg_auto_lock_detected then
            scale_lock_active = true
          end
          generate_all_chords(active_slot_idx)
          validate_slot_chords()
        end

        local icon_btn_w = S(24)
        local icon_btn_h = S(20)
        local icon_btn_x = kx + key_card_w - icon_btn_w - S(6)
        local icon_btn_y = key_card_y + S(6)

        if draw_card(icon_btn_x, icon_btn_y, icon_btn_w, icon_btn_h, Theme.card_active, ">", false, nil, false) then
          preview_scale_run(key.root_idx, key.scale_name)
        end
      end

      local focused_key = detected_keys[focused_key_idx] or {root_name = note_names[current_root_idx], scale_name = SCALE_NAMES[current_scale_idx]}
      local grid_y = key_card_y + (font_h * 2) + S(32)
      
      set_color(Theme.accent)
      gfx.x, gfx.y = pad_x, grid_y
      gfx.drawstr("DIATONIC SUGGESTIONS FOR BEAT " .. active_slot_idx .. " (" .. focused_key.root_name .. " " .. focused_key.scale_name .. ")")
      set_color(Theme.border)
      gfx.line(pad_x, grid_y + font_h + S(4), gfx.w - pad_x, grid_y + font_h + S(4))

      local cols = math.max(3, math.floor(content_w / S(120)))
      local card_w = math.floor((content_w - ((cols - 1) * S(6))) / cols)
      local card_h = font_h + S(14)

      local categories = {"Triads", "7ths", "Extended/Sus"}
      local cur_cat_y = grid_y + font_h + S(10)

      for _, cat in ipairs(categories) do
        local cat_chords = {}
        for _, chord in ipairs(suggested_chords) do
          if chord.category == cat and is_chord_in_scale(chord.pitches, focused_key.root_idx, focused_key.scale_name) then
            table.insert(cat_chords, chord)
          end
        end

        if #cat_chords > 0 then
          set_color(Theme.text_dim)
          gfx.x, gfx.y = pad_x, cur_cat_y
          gfx.drawstr(string.upper(cat))

          local cat_rows = math.ceil(#cat_chords / cols)
          for c_idx, chord in ipairs(cat_chords) do
            local col = (c_idx - 1) % cols
            local row = math.floor((c_idx - 1) / cols)
            local bx = pad_x + col * (card_w + S(6))
            local by = cur_cat_y + font_h + S(4) + row * (card_h + S(6))

            local display_label = get_chord_shifted_label(chord, active_slot_idx)
            local is_assigned = slot_chords[active_slot_idx] and (slot_chords[active_slot_idx].label == chord.label)
            
            if draw_card(bx, by, card_w, card_h, Theme.card, display_label, is_assigned, nil, false) then
              slot_chords[active_slot_idx] = chord
              
              local trigger_id = "TAB2_CHORD_" .. c_idx
              if last_auditioned_id ~= trigger_id then
                local slot_oct = slot_octaves[active_slot_idx] or 0
                local pitches_to_play = {table.unpack(chord.pitches)}
                if cfg_bass_enabled_default then
                  table.insert(pitches_to_play, get_smart_non_overlapping_bass(chord.pitches, slot_oct))
                end
                audition_vst(pitches_to_play, selected_notes[active_slot_idx].chan, selected_notes[active_slot_idx].vel, slot_oct)
                last_auditioned_id = trigger_id
              end
            end
          end
          cur_cat_y = cur_cat_y + font_h + S(6) + (cat_rows * (card_h + S(6))) + S(10)
        end
      end

    else
      local ctrl_y = common_bottom_y
      set_color(Theme.border)
      gfx.line(pad_x, ctrl_y - S(6), gfx.w - pad_x, ctrl_y - S(6))

      local gap = S(6)
      local sync_btn_w = S(110)
      local remaining_w = content_w - sync_btn_w - (gap * 3)
      local ctrl_w = math.floor(remaining_w / 3)
      local ctrl_h = font_h + S(12)

      local new_root = draw_dropdown(pad_x, ctrl_y, ctrl_w, ctrl_h, "Key", note_names, current_root_idx)
      if new_root ~= current_root_idx then
        current_root_idx = new_root
        generate_all_chords(active_slot_idx)
        validate_slot_chords()
      end

      local new_scale = draw_dropdown(pad_x + ctrl_w + gap, ctrl_y, ctrl_w, ctrl_h, "Scale", SCALE_NAMES, current_scale_idx)
      if new_scale ~= current_scale_idx then
        current_scale_idx = new_scale
        generate_all_chords(active_slot_idx)
        validate_slot_chords()
      end

      local lock_text = scale_lock_active and "Lock: ON" or "Lock: OFF"
      local lock_bg = scale_lock_active and Theme.lock_on or Theme.lock_off
      if draw_card(pad_x + (ctrl_w * 2) + (gap * 2), ctrl_y, ctrl_w, ctrl_h, lock_bg, lock_text, false, nil, false) then
        scale_lock_active = not scale_lock_active
        generate_all_chords(active_slot_idx)
        validate_slot_chords()
        last_auditioned_id = ""
      end

      local has_detected = #detected_keys > 0
      local sync_x = pad_x + (ctrl_w * 3) + (gap * 3)
      if draw_card(sync_x, ctrl_y, sync_btn_w, ctrl_h, Theme.accent_sec, "USE DETECTED", false, nil, not has_detected) then
        sync_to_detected_key()
      end

      local oct_y = ctrl_y + ctrl_h + S(8)
      set_color(Theme.text_dim)
      gfx.x, gfx.y = pad_x, oct_y + S(3)
      gfx.drawstr("Voicing:")
      
      local octaves = {-2, -1, 0, 1, 2}
      local oct_btn_w = math.min(S(42), math.floor((content_w - S(80)) / 5))
      for idx, oct in ipairs(octaves) do
        local ox = pad_x + S(75) + (idx - 1) * (oct_btn_w + S(4))
        local label = (oct > 0 and "+" or "") .. oct
        if draw_card(ox, oct_y, oct_btn_w, font_h + S(10), Theme.card, label, octave_offset == oct, nil, false) then
          octave_offset = oct
          generate_all_chords(active_slot_idx)
          last_auditioned_id = ""
        end
      end

      local num_chord_defs = #base_chords
      local cols = math.min(num_chord_defs, math.max(4, math.floor(content_w / S(105))))
      local card_w = math.floor((content_w - ((cols - 1) * S(6))) / cols)
      local card_h = font_h + S(14)

      local top_sec_y = oct_y + font_h + S(22)
      set_color(Theme.accent)
      gfx.x, gfx.y = pad_x, top_sec_y
      gfx.drawstr("TOP NOTE MATCHING CHORDS")
      set_color(Theme.border)
      gfx.line(pad_x, top_sec_y + font_h + S(4), gfx.w - pad_x, top_sec_y + font_h + S(4))

      local top_rows = math.ceil(num_chord_defs / cols)
      for c_idx = 1, num_chord_defs do
        local chord = top_note_chords[c_idx]
        if chord then
          local col = (c_idx - 1) % cols
          local row = math.floor((c_idx - 1) / cols)
          local bx = pad_x + col * (card_w + S(6))
          local by = top_sec_y + font_h + S(10) + row * (card_h + S(6))

          local display_label = get_chord_shifted_label(chord, active_slot_idx)
          local is_current_assigned = slot_chords[active_slot_idx] and (slot_chords[active_slot_idx].label == chord.label)
          local is_disabled = scale_lock_active and not chord.in_scale
          
          if draw_card(bx, by, card_w, card_h, Theme.card, display_label, is_current_assigned, nil, is_disabled) then
            slot_chords[active_slot_idx] = chord
            
            local trigger_id = "TOP_CHORD_" .. c_idx
            if last_auditioned_id ~= trigger_id then
              local slot_oct = slot_octaves[active_slot_idx] or 0
              local pitches_to_play = {table.unpack(chord.pitches)}
              if cfg_bass_enabled_default then
                table.insert(pitches_to_play, get_smart_non_overlapping_bass(chord.pitches, slot_oct))
              end
              audition_vst(pitches_to_play, selected_notes[active_slot_idx].chan, selected_notes[active_slot_idx].vel, slot_oct)
              last_auditioned_id = trigger_id
            end
          end
        end
      end

      local section_titles = {[0] = "ROOT POSITION", [1] = "FIRST INVERSION", [2] = "SECOND INVERSION"}
      local start_y = top_sec_y + font_h + S(10) + (top_rows * (card_h + S(6))) + S(12)

      for inv = 0, 2 do
        local sec_y = start_y
        
        set_color(Theme.accent)
        gfx.x, gfx.y = pad_x, sec_y
        gfx.drawstr(section_titles[inv])
        set_color(Theme.border)
        gfx.line(pad_x, sec_y + font_h + S(4), gfx.w - pad_x, sec_y + font_h + S(4))

        local inv_rows = math.ceil(num_chord_defs / cols)

        for def_i = 1, num_chord_defs do
          local target_chord = nil
          for _, c in ipairs(suggested_chords) do
            if c.inversion == inv and c.def_idx == def_i then
              target_chord = c
              break
            end
          end

          local col = (def_i - 1) % cols
          local row = math.floor((def_i - 1) / cols)
          local bx = pad_x + col * (card_w + S(6))
          local by = sec_y + font_h + S(10) + row * (card_h + S(6))

          if target_chord then
            local display_label = get_chord_shifted_label(target_chord, active_slot_idx)
            local is_current_assigned = slot_chords[active_slot_idx] and (slot_chords[active_slot_idx].label == target_chord.label)
            local is_disabled = scale_lock_active and not target_chord.in_scale
            
            if draw_card(bx, by, card_w, card_h, Theme.card, display_label, is_current_assigned, nil, is_disabled) then
              slot_chords[active_slot_idx] = target_chord
              
              local trigger_id = "CHORD_" .. inv .. "_" .. def_i
              if last_auditioned_id ~= trigger_id then
                local slot_oct = slot_octaves[active_slot_idx] or 0
                local pitches_to_play = {table.unpack(target_chord.pitches)}
                if cfg_bass_enabled_default then
                  table.insert(pitches_to_play, get_smart_non_overlapping_bass(target_chord.pitches, slot_oct))
                end
                audition_vst(pitches_to_play, selected_notes[active_slot_idx].chan, selected_notes[active_slot_idx].vel, slot_oct)
                last_auditioned_id = trigger_id
              end
            end
          else
            draw_card(bx, by, card_w, card_h, Theme.disabled, "---", false, nil, true)
          end
        end
        
        start_y = start_y + font_h + S(10) + (inv_rows * (card_h + S(6))) + S(12)
      end
    end

    if gfx.mouse_cap & 1 == 0 then
      last_auditioned_id = ""
    end

    local footer_panel_h = font_h + S(28)
    local footer_y = math.max(top_offset + S(320), gfx.h - footer_panel_h - S(48))

    set_color(Theme.panel)
    gfx.rect(pad_x, footer_y, content_w, footer_panel_h, 1)
    set_color(Theme.border)
    gfx.rect(pad_x, footer_y, content_w, footer_panel_h, 0)

    set_color(Theme.text_sub)
    gfx.x, gfx.y = pad_x + S(8), footer_y + S(6)
    gfx.drawstr("Stack:")

    local stack_labels = {"Replace", "Smart Above", "Smart Below"}
    local stack_opt_w = math.min(S(85), math.floor((content_w - S(40)) / 3))

    for i = 1, 3 do
      local ox = pad_x + S(55) + (i - 1) * (stack_opt_w + S(4))
      if draw_card(ox, footer_y + S(4), stack_opt_w, font_h + S(8), Theme.card, stack_labels[i], cfg_stack_mode == i, nil, false) then
        cfg_stack_mode = i
        save_settings()
      end
    end

    local btn_h = font_h + S(18)
    local apply_x = (gfx.w / 2) - (content_w / 2)
    local btn_y = footer_y + footer_panel_h + S(6)

    if draw_card(apply_x, btn_y, content_w, btn_h, Theme.accent, "APPLY PROGRESSION", false, nil, false) then
      insert_all_chords()
    end
  end

  mouse_was_down = (gfx.mouse_cap & 1 == 1)

  local char = gfx.getchar()
  if char == 13 then insert_all_chords()  end
  
  if char >= 0 then 
    reaper.defer(main) 
  else
    cleanup_instance()
  end
  
  gfx.update()
end

load_settings()
gfx.init("ReaHarmonizer V9.8", math.floor(680 * current_scale_factor), math.floor(820 * current_scale_factor), 0)
main()
