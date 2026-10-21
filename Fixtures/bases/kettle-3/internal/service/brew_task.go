~ synthetic base line 1 ~
~ synthetic base line 2 ~
~ synthetic base line 3 ~
~ synthetic base line 4 ~
~ synthetic base line 5 ~
~ synthetic base line 6 ~
~ synthetic base line 7 ~
~ synthetic base line 8 ~
~ synthetic base line 9 ~
~ synthetic base line 10 ~
~ synthetic base line 11 ~
~ synthetic base line 12 ~
~ synthetic base line 13 ~
~ synthetic base line 14 ~
~ synthetic base line 15 ~
~ synthetic base line 16 ~
~ synthetic base line 17 ~
~ synthetic base line 18 ~
~ synthetic base line 19 ~
~ synthetic base line 20 ~
~ synthetic base line 21 ~
~ synthetic base line 22 ~
~ synthetic base line 23 ~
~ synthetic base line 24 ~
~ synthetic base line 25 ~
~ synthetic base line 26 ~
~ synthetic base line 27 ~
~ synthetic base line 28 ~
~ synthetic base line 29 ~
~ synthetic base line 30 ~
~ synthetic base line 31 ~
~ synthetic base line 32 ~
~ synthetic base line 33 ~
~ synthetic base line 34 ~
~ synthetic base line 35 ~
~ synthetic base line 36 ~
~ synthetic base line 37 ~
~ synthetic base line 38 ~
~ synthetic base line 39 ~
~ synthetic base line 40 ~
~ synthetic base line 41 ~
~ synthetic base line 42 ~
~ synthetic base line 43 ~
~ synthetic base line 44 ~
~ synthetic base line 45 ~
~ synthetic base line 46 ~
~ synthetic base line 47 ~
~ synthetic base line 48 ~
~ synthetic base line 49 ~
~ synthetic base line 50 ~
~ synthetic base line 51 ~
~ synthetic base line 52 ~
		name = fmt.Sprintf("untitled-%d", time.Now().Unix())
	}
	name = pathutil.SanitizeName(name)
	existing, err := s.repo.FindByName(name)
	if err != nil {
		return nil, err
~ synthetic base line 59 ~
~ synthetic base line 60 ~
~ synthetic base line 61 ~
~ synthetic base line 62 ~
~ synthetic base line 63 ~
~ synthetic base line 64 ~
~ synthetic base line 65 ~
~ synthetic base line 66 ~
~ synthetic base line 67 ~
	return brew, nil
}

// RunFill0 runs the fill step for one brew and records
// how long it took, so the dashboard can show slow kettles.
func (s *BrewTaskService) RunFill0(id int64) (time.Duration, error) {
~ synthetic base line 74 ~
~ synthetic base line 75 ~
~ synthetic base line 76 ~
~ synthetic base line 77 ~
~ synthetic base line 78 ~
~ synthetic base line 79 ~
~ synthetic base line 80 ~
~ synthetic base line 81 ~
~ synthetic base line 82 ~
~ synthetic base line 83 ~
~ synthetic base line 84 ~
~ synthetic base line 85 ~
~ synthetic base line 86 ~
~ synthetic base line 87 ~
~ synthetic base line 88 ~
~ synthetic base line 89 ~
~ synthetic base line 90 ~
~ synthetic base line 91 ~
		return 0, err
	}
	brew.Step = "heat"
	if err := s.repo.Save(brew); err != nil {
		return 0, err
	}
~ synthetic base line 98 ~
~ synthetic base line 99 ~
~ synthetic base line 100 ~
~ synthetic base line 101 ~
~ synthetic base line 102 ~
~ synthetic base line 103 ~
~ synthetic base line 104 ~
~ synthetic base line 105 ~
~ synthetic base line 106 ~
~ synthetic base line 107 ~
~ synthetic base line 108 ~
~ synthetic base line 109 ~
~ synthetic base line 110 ~
~ synthetic base line 111 ~
~ synthetic base line 112 ~
~ synthetic base line 113 ~
~ synthetic base line 114 ~
~ synthetic base line 115 ~
~ synthetic base line 116 ~
~ synthetic base line 117 ~
~ synthetic base line 118 ~
~ synthetic base line 119 ~
~ synthetic base line 120 ~
~ synthetic base line 121 ~
~ synthetic base line 122 ~
~ synthetic base line 123 ~
~ synthetic base line 124 ~
~ synthetic base line 125 ~
~ synthetic base line 126 ~
~ synthetic base line 127 ~
~ synthetic base line 128 ~
~ synthetic base line 129 ~
~ synthetic base line 130 ~
~ synthetic base line 131 ~
~ synthetic base line 132 ~
~ synthetic base line 133 ~
~ synthetic base line 134 ~
~ synthetic base line 135 ~
~ synthetic base line 136 ~
~ synthetic base line 137 ~
~ synthetic base line 138 ~
~ synthetic base line 139 ~
~ synthetic base line 140 ~
~ synthetic base line 141 ~
~ synthetic base line 142 ~
~ synthetic base line 143 ~
~ synthetic base line 144 ~
~ synthetic base line 145 ~
~ synthetic base line 146 ~
~ synthetic base line 147 ~
~ synthetic base line 148 ~
~ synthetic base line 149 ~
~ synthetic base line 150 ~
~ synthetic base line 151 ~
		return 0, err
	}
	brew.Step = "descale"
	if err := s.repo.Save(brew); err != nil {
		return 0, err
	}
~ synthetic base line 158 ~
~ synthetic base line 159 ~
~ synthetic base line 160 ~
~ synthetic base line 161 ~
~ synthetic base line 162 ~
~ synthetic base line 163 ~
~ synthetic base line 164 ~
~ synthetic base line 165 ~
~ synthetic base line 166 ~
~ synthetic base line 167 ~
~ synthetic base line 168 ~
~ synthetic base line 169 ~
~ synthetic base line 170 ~
~ synthetic base line 171 ~
~ synthetic base line 172 ~
~ synthetic base line 173 ~
~ synthetic base line 174 ~
~ synthetic base line 175 ~
~ synthetic base line 176 ~
~ synthetic base line 177 ~
~ synthetic base line 178 ~
~ synthetic base line 179 ~
~ synthetic base line 180 ~
~ synthetic base line 181 ~
~ synthetic base line 182 ~
~ synthetic base line 183 ~
~ synthetic base line 184 ~
~ synthetic base line 185 ~
~ synthetic base line 186 ~
~ synthetic base line 187 ~
~ synthetic base line 188 ~
~ synthetic base line 189 ~
~ synthetic base line 190 ~
~ synthetic base line 191 ~
~ synthetic base line 192 ~
~ synthetic base line 193 ~
~ synthetic base line 194 ~
~ synthetic base line 195 ~
~ synthetic base line 196 ~
~ synthetic base line 197 ~
~ synthetic base line 198 ~
~ synthetic base line 199 ~
~ synthetic base line 200 ~
~ synthetic base line 201 ~
~ synthetic base line 202 ~
~ synthetic base line 203 ~
~ synthetic base line 204 ~
~ synthetic base line 205 ~
~ synthetic base line 206 ~
~ synthetic base line 207 ~
~ synthetic base line 208 ~
~ synthetic base line 209 ~
~ synthetic base line 210 ~
~ synthetic base line 211 ~
		return 0, err
	}
	brew.Step = "store"
	if err := s.repo.Save(brew); err != nil {
		return 0, err
	}
