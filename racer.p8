pico-8 cartridge // http://www.pico-8.com
version 8
__lua__

sfx_boost_cooldown=33
sfx_booster=41

boost_warning_thresh=30
boost_critical_thresh=15

cars = {
	{
		name="easy",
		maxacc=1.5,
		steer=0.0425,
		accsqr=0.1
	},
	{
		name="medium",
		maxacc=2,
		steer=0.0325,
		accsqr=0.15
	},
	{
		name="hard",
		maxacc=2.5,
		steer=0.0225,
		accsqr=0.2
	}
}

track_colors = {
	8,9,10,11,12,3,14,15
}
dt=0.033333
-- globals

particles = {}
mapsize = 250

function ai_controls(car)
	-- look ahead 5 segments
	local ai = {
		decisions = rnd(5)+3,
		target_seg = 1,
		riskiness = rnd(23)+1
	}
	ai.car = car
	function ai:update()
		self.decisions += dt*(self.skill+rnd(6))
		local c = car.controls
		local car = self.car
		if not car.current_segment then return end
		local s = flr(2*car.maxacc)
		if self.decisions < 1 then
			return
		end
		local t = car.current_segment+s
		if t < (mapsize*3) + 10 then
			local v5 = get_vec_from_vecmap(t)
			if v5 then
				local a = atan2(v5.x-car.pos.x,v5.y-car.pos.y)
				local diff = a-car.angle
				while diff > 0.5 do diff -= 1 end
				while diff < -0.5 do diff += 1 end
				if abs(diff) > 0.02 and rnd(50) > 40+self.skill then
					self.decisions = 0
				end
				local steer = car.steer
				c.accel = abs(diff) < steer*100
				c.right = diff < -steer/3
				c.left = diff > steer/3
				c.brake = abs(diff) > steer
				c.boost = car.boost > 24-self.riskiness and (abs(diff) < steer/2 or car.accel < 0.5)
				self.decisions -=1
			--break
			end
		else
			c.accel = false
			c.boost = false
			c.brake = true
		end
	end
	return ai
end

function create_car(race)
	c = cars[intro.car]
	local car = {
		race=race,
		vel=vec(),
		angle=0,
		trails = cbufnew(32),
		current_segment = -3,
		boost=100,
		cooldown=0,
		wrong_way=0,
		speed=0,
		accel=0,
		accsqr=c.accsqr,
		steer=c.steer,
		maxacc=c.maxacc,
		maxboost=c.maxacc*1.5,
		lost_count=0,
		last_good_pos=vec(),
		last_good_seg=1,
		color=8,
		collision=0,
	}
	car.controls = {
	}
	car.pos = copyv(get_vec_from_vecmap(car.current_segment))
	function car:get_poly()
		return fmap(car_verts,function(i) return rotate_point(vecadd(self.pos,i),angle,self.pos) end)
	end
	function car:update()
		local angle = self.angle
		local pos = self.pos
		local vel = self.vel
		local accel = self.accel
		local controls = self.controls

		if controls.accel then
			accel+=self.accsqr*0.3
		else
			accel*=0.98
		end
		local speed = length(vel)
		-- accelerate
		if controls.left then angle+=self.steer*0.3 end
		if controls.right then angle-=self.steer*0.3 end
		-- brake
		local sb_left
		local sb_right
		if controls.brake then
			if controls.left then
				sb_left = true
			elseif controls.right then
				sb_right = true
			else
				sb_left = true
				sb_right = true
			end
			if sb_left then
				angle += speed*0.001
			end
			if sb_right then
				angle -= speed*0.001
			end
			vel = scalev(vel,0.95)
		end
		accel=min(accel,self.boosting and self.maxboost or self.maxacc)
		-- boosting

		if controls.boost and self.boost > 0 and self.cooldown <= 0 then
			self.boosting = true
			self.boost -= 1
			self.boost = max(self.boost,0)
			accel+=self.accsqr*0.3

			if self.boost == 0 then -- activate cooldown
				self.cooldown = 25
				accel*=0.5
				if self.is_player then
					sfx(sfx_boost_cooldown,0)
					sc1=sfx_boost_cooldown
				end
			elseif self.is_player and (not (sc1 == sfx_booster and sc1timer > 0)) and sc1 != 39 and self.boost <= boost_critical_thresh then
				sfx(39,0)
				sc1=39
			elseif self.is_player and (not (sc1 == sfx_booster and sc1timer > 0)) and sc1 != 37 and self.boost <= boost_warning_thresh then
				sfx(37,0) -- start warning
				sc1=37
			elseif self.is_player and (not (sc1 == sfx_booster and sc1timer > 0)) and sc1 != 36 and sc1 != 37 then
				sfx(36,0)
				sc1=36
			end
		else
			self.boosting = false
			if self.cooldown > 0 then
				self.cooldown -= 0.25
				self.cooldown = max(self.cooldown,0)
				if self.is_player and self.cooldown == 0 then
					sfx(34,0) -- restore power
					sc1=34
				end
				self.boost += 0.125
			else
				self.boost += 0.25
				self.boost = min(self.boost,100)
			end
			if self.is_player and (sc1==37 or sc1==39 or sc1==36 or ((sc1==38 or sc1==40) and self.collision <= 0) or (sc1 == 34 and self.boost > 10)) then
				-- engine noise
				sfx(35,0)
				sc1=35
			end
		end

		-- check collisions
		-- get a width enlarged version of this segment to help prevent losing the car
		local current_segment = self.current_segment
		local segpoly = get_segment(current_segment,true)
		local poly

		self.collision = 0
		if segpoly then
			local in_current_segment = point_in_polygon(segpoly,self.pos)
			if in_current_segment then
				self.last_good_pos = self.pos
				self.last_good_seg = current_segment
				self.lost_count = 0
				poly = get_segment(current_segment)
			else
				-- not found in current segment, try the next
				local segnextpoly = get_segment(current_segment+1,true)
				if segnextpoly and point_in_polygon(segnextpoly,self.pos) then
					poly = get_segment(current_segment+1)
					current_segment+=1
					self.wrong_way=0
				else
					-- not found in current or next, try the previous one
					local segprevpoly = get_segment(current_segment-1,true)
					if segprevpoly and point_in_polygon(segprevpoly,self.pos) then
						poly = get_segment(current_segment-1)
						current_segment-=1
						self.wrong_way+=1
					else
						-- completely lost the player
						self.lost_count += 1
						--current_segment+=1 -- try to find the car next frame
						if self.lost_count > 30 then
							-- lost for too long, bring them back to the last known good position
							local v = get_vec_from_vecmap(self.last_good_seg)
							self.pos = copyv(v)
							self.current_segment = self.last_good_seg-2
							self.vel = vec(0,0)
							self.angle = v.dir
							self.wrong_way = 0
							self.accel = 1
							self.lost_count = 0
							self.trails = cbufnew(32)
							return
						end
					end
				end
			end
			-- check collisions with walls
			if poly then
				local car_poly = self:get_poly""
				local rv,pen,point = check_collision(car_poly,{{poly[2],poly[3]},{poly[4],poly[1]}})
				if rv then
					if pen > 5 then pen = 5 end
					vel = vecsub(vel,scalev(rv,pen))
					accel*=1.0 - (pen/10)
					add(particles,{x=point.x,y=point.y,xv=-rv.x+(rnd(2)-1)/2,yv=-rv.y+(rnd(2)-1)/2,ttl=30})
					self.collision += pen
					if self.is_player then
						if pen > 2 then
							sfx(38,0)
							sc1=38
						else
							sfx(40,0)
							sc1=40
						end
					end
				end
			end
		end
		-- check for boosters under us
		--if current_segment then
		--	for b in all(boosters) do
		--		if b.segment <= current_segment+1 and b.segment >= current_segment-1 then
		--			local bx = b.x
		--			local by = b.y
		--			local pa = rotate_point(bx-12,by-12,b.dir,bx,by)
		--			local pb = rotate_point(bx+12,by-12,b.dir,bx,by)
		--			local pc = rotate_point(bx+12,by+12,b.dir,bx,by)
		--			local pd = rotate_point(bx-12,by+12,b.dir,bx,by)
		--			if point_in_polygon({pa,pb,pc,pd},vec(x,y)) then
		--				xv*=1.25
		--				yv*=1.25
		--				if self.is_player then
		--					sfx(sfx_booster,0)
		--					sc1=sfx_booster
		--					sc1timer=10
		--				end
		--			end
		--		end
		--	end
		--end

		local car_dir = vec(cos(angle),sin(angle))
		self.vel = vecadd(vel,scalev(car_dir,accel))
		self.pos = vecadd(self.pos,scalev(self.vel,0.3))
		self.vel = scalev(self.vel,0.9)

		cbufpush(self.trails,rotate_point(vecadd(self.pos,trail_offset),angle,self.pos))

		-- update self attrs
		self.accel = accel
		self.speed = speed -- used for showing speedo
		self.angle = angle
		self.current_segment = current_segment
	end
	function car:draw()
		local angle = self.angle
		local color = self.color
		local v = fmap(car_verts,function(i) return rotate_point(vecadd(self.pos,i),angle,self.pos) end)
		local a = v[1]
		local b = v[2]
		local c = v[3]
		local boost = self.boost
		linevec(a,b,color)
		linevec(b,c,color)
		linevec(c,a,color)
		local circ = rotate_point(vecadd(self.pos,trail_offset),angle,self.pos)
		local outc = 12
		if self.boost and self.boost < 30 then
			outc = self.boost < 15 and 8 or 9
		end
		local cx,cy = circ.x,circ.y
		if self.cooldown > 0 then
			circfill(cx,cy,frame%8 < 4 and 1 or 0,8)
		else
			circfill(cx,cy,self.boosting and frame%2 == 0 and 4 or 2,outc)
			circfill(cx,cy,self.boosting and frame%2 == 0 and 2 or 1,7)
		end

	end

	function car:draw_trails()
		-- trails
		local lastp
		for i=0,self.trails._size-1 do
			local p = cbufget(self.trails,-i)
			if not p then break end
			if lastp then
				linevec(lastp,p,i > self.trails._size - 4 and 7 or (i < 12 and 1 or 12))
			end
			lastp = p
		end
	end

	return car
end

function set_game_mode(m)
	game_mode = m
end

function _init()
	car_verts = {
		vec(-4,-3),
		vec(4, 0),
		vec(-4, 3)
	}

	trail_offset = vec(-6,0)


	intro:init""
	set_game_mode(intro)
end

function _draw()
	game_mode:draw""
end

function _update()
	game_mode:update""
end

-- intro

intro = {}
frame = 0

game_modes = {
	"race vs ai",
	"time attack",
	"track editor"
}

function intro:init()
	--music(0)
	difficulty = 0
	load_map""
	self.game_mode = 1
	self.car = 1
end

function intro:update()
	frame+=1

	if not btn(4) then self.ready = true end

	if self.ready and btnp(4) then
		if self.game_mode == 3 then
			mapeditor:init()
			set_game_mode(mapeditor)
		else
			local race = race""
			race:init(difficulty,self.game_mode)
			set_game_mode(race)
		end
	end

	if self.option == 1 then
		if btnp(0) then self.game_mode -= 1 end
		if btnp(1) then self.game_mode += 1 end
	elseif self.option == 2 then
		if btnp(0) then
			difficulty = mid(0,difficulty-1,7)
			load_map""
		end
		if btnp(1) then
			difficulty = mid(0,difficulty+1,7)
			load_map""
		end
	elseif self.option == 3 then
		if btnp(0) then self.car -= 1 end
		if btnp(1) then self.car += 1 end
	end
	if btnp(2) then self.option -= 1 end
	if btnp(3) then self.option += 1 end
	self.game_mode = mid(1,self.game_mode,3)
	self.option = mid(1,self.option,3)
	self.car = mid(1,self.car,3)
end

difficulty_names = {
	[0]="berlin",
	"vancouver",
	"melbourne",
	"detroit",
	"jakarta",
	"wellington",
	"hanoi",
	"osaka",
}

function intro:draw()
	cls""
	sspr(0,20,128,128,0,0)

	draw_minimap(40,50,0.025,6)


	printr("z - accel",127,40,6)
	printr("x - brake",127,48,6)
	printr("up - boost",127,56,6)
	printr("< > - steer",127,64,6)
	printr("tab -  menu",127,72,6)

	local c = frame%16<8 and 8 or 9
	printr("mode",127,2,self.option == 1 and c or 9)
	printr(game_modes[self.game_mode],127,8,6)
	printr("track",128,16,self.option == 2 and c or 9)
	printr(difficulty_names[difficulty],128,22,6)
	printr(cars[self.car].name,128,30,self.option == 3 and c or 9)
end

mapeditor = {}
function mapeditor:init()
	scale = 0.05
end

function map_menu(game)
	local selected = 1
	local m = {}
	function m:update()
		frame+=1
		if btnp(2) then selected -= 1 end
		if btnp(3) then selected += 1 end
		selected = max(min(selected,3),1)
		if btnp(4) then
			if selected == 1 then
				set_game_mode(game)
			elseif selected == 2 then
				local start = 0x2000 + (difficulty*512)
				local offset = start
				for i=1,#mapsections do
					local ms = mapsections[i]
					poke(offset,ms[1])
					poke(offset+1,ms[2])
					poke(offset+2,ms[3])
					offset += 3
				end
				poke(offset,0)
				poke(offset,0)
				poke(offset,0)
				cstore(start,start,512)
				save("picopout.p8")
				local race = race""
				race:init(difficulty,2)
				set_game_mode(race)
				return
			elseif selected == 3 then
				set_game_mode(intro)
			end
		end
	end
	function m:draw()
		game:draw""
		rectfill(35,40,93,88,1)
		print("editor",40,44,7)
		print("continue",40,56,selected == 1 and frame%4<2 and 7 or 6)
		print("test track",40,62,selected == 2 and frame%4<2 and 7 or 6)
		print("exit",40,70,selected == 3 and frame%4<2 and 7 or 6)
	end
	return m
end

function mapeditor:update()
	local cs = mapsections[#mapsections]
	if btnp(0) then
		cs[2] -= 1
	elseif btnp(1,0) then
		cs[2] += 1
	elseif btnp(2,0) then
		cs[1] += 1
	elseif btnp(3,0) then
		cs[1] -= 1
	elseif btnp(4,0) then
		mapsections[#mapsections] = nil
	elseif btnp(5,0) then
		mapsections[#mapsections+1] = {cs[1],cs[2],cs[3]}
	elseif btnp(0,1) then
		cs[3] -= 1
	elseif btnp(1,1) then
		cs[3] += 1
	elseif btnp(2,1) then
		scale *= 0.9
	elseif btnp(3,1) then
		scale *= 1.1
	elseif btnp(4,1) then
		-- test map todo: open menu
		set_game_mode(map_menu(self))
		return
	end
	cs[2] = mid(0,cs[2],255)
	cs[1] = mid(0,cs[1],255)
end

function draw_minimap(sx,sy,scale,col)
	local x,y=sx,sy
	local lastx,lasty = sx,sy
	local dir = 0
	for i=1,#mapsections do
		ms = mapsections[i]
		for seg=1,ms[1] do
			dir += (ms[2] - 128) / 100
			x += cos(dir)*32*scale
			y += sin(dir)*32*scale
			line(lastx,lasty,x,y,#mapsections == i and 3 or col)
			lastx,lasty = x,y
		end
	end
end

function mapeditor:draw()
	cls()
	draw_minimap(64,64,scale,6)
	print(#mapsections..'/'..flr(0x1000/8/3), 2,2,7)
end

function load_map()
	local start = 0x2000 + (difficulty * 512)
	mapsections = {}
	while true do
		local ms = {}
		ms[1] = peek(start)
		ms[2] = peek(start+1)
		ms[3] = peek(start+2)
		if ms[1] == 0 then break end
		mapsections[#mapsections+1] = ms
		start += 3
	end
	if #mapsections == 0 then
		mapsections[1] = {10,128,32}
	end
	printh("loaded "..#mapsections.." sections")
end

function race()
	local race = {}
	function race:init(difficulty,race_mode)
		self.race_mode = race_mode
		sc1=nil
		sc1timer=0

		vecmap = {}
		boosters = {}
		local dir,mx,my=0,0,0
		local lastdir = 0

		-- generate map
		for ms in all(mapsections) do
			-- read length,curve,width from tiledata
			local length = ms[1]
			local curve  = ms[2]
			local width  = ms[3]

			if length == 0 then
				break
			end

			while length > 0 do
				dir += (curve - 128) / 100

				if abs(dir-lastdir) > 0.09 then
					dir = lerp(lastdir,dir,0.5)
					segment_length = 16
					length -= 0.5
				else
					segment_length = 32
					length -= 1
				end

				mx+=cos(dir)*segment_length
				my+=sin(dir)*segment_length
				add(vecmap,mx)
				add(vecmap,my)
				add(vecmap,width)
				add(vecmap,dir)

				mapsize += 1

				lastdir = dir
			end
		end
		
		mapsize = #vecmap / 4

		self:restart""
	end

	function race:restart()
		self.completed = false
		self.time = self.race_mode == 1 and -3 or 0
		self.previous_best = nil
		camera_lastpos = vec()
		self.start_timer = self.race_mode == 1
		self.record_replay = nil
		self.play_replay_step = 1
		-- spawn cars

		self.objects = {}

		if self.race_mode == 2 and self.play_replay then
			local replay_car = create_car(self)
			add(self.objects,replay_car)
			replay_car.color = 1
			self.replay_car = replay_car
		end

		local p = create_car(self)
		add(self.objects,p)
		self.player = p
		p.is_player = true

		if self.race_mode == 1 then
			for i=1,3 do
				local ai_car = create_car(self)
				ai_car.color = rnd(6)+9
				local v = get_vec_from_vecmap(-3-i)
				ai_car.pos = copyv(v)
				ai_car.angle = v.dir
				local oldupdate = ai_car.update
				ai_car.ai = ai_controls(ai_car)
				global_ai = ai_car.ai
				global_ai.skill = i+4
				function ai_car:update()
					self.ai:update""
					oldupdate(self)
				end
				add(self.objects,ai_car)
			end
		end


	end

	function race:update()
		frame+=1
		if sc1timer > 0 then
			sc1timer-=1
		end

		if self.completed then
			self.completed_countdown -= dt
			if self.completed_countdown < 4 then
				set_game_mode(completed_menu(self))
				return
			end
		end

		if btn(4,1) then
			set_game_mode(paused_menu(self))
			return
		end

		-- enter input
		local player = self.player
		if player then
			local controls = player.controls
			controls.left = btn(0)
			controls.right = btn(1)
			controls.boost = btn(2)
			controls.accel = btn(4)
			controls.brake = btn(5)
		end

		-- replay playback
		local replay = self.play_replay
		if replay and self.replay_car then
			if self.play_replay_step == 1 then
				self.replay_car.pos = replay[1].pos
				self.replay_car.angle = replay[1].angle
				self.play_replay_step=2
			end
			if self.start_timer then
				if self.play_replay_step == 2 then
					local rc = self.replay_car
					rc.vel   = replay[1].vel
					rc.accel = replay[1].accel
					rc.boost = replay[1].boost
				end
				local v = replay[self.play_replay_step]
				if v then
					local c = self.replay_car.controls
					c.left  = band(v,1) != 0
					c.right = band(v,2) != 0
					c.accel = band(v,4) != 0
					c.brake = band(v,8) != 0
					c.boost = band(v,16) != 0
					self.play_replay_step+=1
				end
			end
		end

		if player.current_segment == 0 and not self.start_timer and self.race_mode == 2 then
			self.start_timer = true
			self.record_replay = {}
			add(self.record_replay,{pos=copyv(player.pos),vel=copyv(player.vel),angle=player.angle,accel=player.accel,boost=player.boost})
		end
		if self.start_timer then
			self.time += dt
		end

		-- record replay
		if self.record_replay then
			local c = player.controls
			local v = (c.left  and 1  or 0)
					+ (c.right and 2  or 0)
					+ (c.accel and 4  or 0)
					+ (c.brake and 8  or 0)
					+ (c.boost and 16 or 0)
			add(self.record_replay,v)
		end

		if self.race_mode == 2 or self.time > 0 then
			for obj in all(self.objects) do
				obj:update""
			end
		end

		-- car to car collision
		for obj in all(self.objects) do
			for obj2 in all(self.objects) do
				if obj != obj2 and obj != self.replay_car and obj2 != self.replay_car then
					if abs(obj.current_segment-obj2.current_segment) <= 1 then
						local p1 = obj:get_poly""
						local p2 = obj2:get_poly""
						for point in all(p1) do
							if point_in_polygon(p2,point) then
								local rv,p,point = check_collision(p1,{{p2[2],p2[1]},{p2[3],p2[2]},{p2[1],p2[3]}})
								if rv then
									if p > 5 then p = 5 end
									p*=1.5
									obj.vel = vecadd(obj.vel,scalev(rv,p))
									obj2.vel = vecsub(obj2.vel,scalev(rv,p))
									add(particles,{x=point.x,y=point.y,xv=-rv.x+(rnd(2)-1)/2,yv=-rv.y+(rnd(2)-1)/2,ttl=30})
									obj.collision += flr(p)
									obj2.collision += flr(p)
									if obj.is_player or obj2.is_player then
										if p > 2 then
											sfx(38,0)
											sc1=38
										else
											sfx(40,0)
											sc1=40
										end
									end
								end
							end
						end
					end
				end
			end
		end

		if player.current_segment == mapsize*3 then
			-- completed
			self.completed = true
			self.completed_countdown = 5
			self.start_timer = false
			if (not self.best_time) or self.time < self.best_time then
				if self.best_time then
					self.previous_best = self.best_time
				end
				self.best_time = self.time
				self.play_replay = self.record_replay
			end
		end


		-- particles
		for p in all(particles) do
			p.x += p.xv
			p.y += p.yv
			p.xv *= 0.95
			p.yv *= 0.95
			p.ttl -= 1
			if p.ttl < 0 then
				del(particles,p)
			end
		end


	end

	function race:draw()
		--local player = global_ai.car
		player = self.player
		time = self.time
		cls""

		local tp = cbufget(player.trails,player.trails._size-8) or player.pos
		local trail = clampv(vecsub(player.pos,tp),54)
		camera_pos = vecadd(vecadd(player.pos,trail),vec(-64,-64))
		if player.collision > 0 then
			camera(camera_pos.x+rnd(3)-2,camera_pos.y+rnd(3)-2)
		else
			local c = lerpv(camera_lastpos,camera_pos,1)
			camera(c.x,c.y)
		end

		camera_lastpos = copyv(camera_pos)

		local current_segment = player.current_segment
		-- draw track
		local lastv
		for seg=current_segment-20,current_segment+20 do
			local v = get_vec_from_vecmap(seg)
			local diff = perpendicular(normalize(lastv and vecsub(v,lastv) or vec(1,0)))
			local offset = scalev(diff,v.w)
			up   = vecsub(v,offset)
			down = vecadd(v,offset)
			offset = scalev(diff,v.w-8)
			up2   = vecsub(v,offset)
			down2 = vecadd(v,offset)
			offset = scalev(diff,v.w+4)
			up3   = vecsub(v,offset)
			down3 = vecadd(v,offset)

			if lastv then
				if onscreen(v) or onscreen(lastv) or onscreen(up) or onscreen(down) then

					--linevec(lastv,v,15)
					--linevec(vecsub(v,offset),vecadd(v,offset),8)

					-- inner track
					local track_color = (seg < current_segment-10 or seg > current_segment+10) and 1 or (seg%2==0 and 13 or 5)
					if seg > current_segment-5 and seg < current_segment+7 then
						if seg >= current_segment-2 and seg < current_segment+7 then
							linevec(lastup2,up2,track_color) -- mid upper
							linevec(lastdown2,down2,track_color) -- mid lower
						end

						-- look for upcoming turns and draw arrows
						-- scan foward until we find a turn sharper than 2/100
						for j=seg+2,seg+7 do
							local v1 = get_vec_from_vecmap(j)
							local v2 = get_vec_from_vecmap(j+1)
							if v1 and v2 and v1.dir and v2.dir then
								-- find the difference in angle between v and v2
								local diff = v2.dir - v1.dir
								while diff > 0.5 do diff -= 1 end
								while diff < -0.5 do diff += 1 end
								if diff > 0.03 then
									-- arrow left
									draw_arrow(lastup2,4,v.dir+0.25,9)
									break
								elseif diff < -0.03 then
									-- arrow right
									draw_arrow(lastdown2,4,v.dir-0.25,9)
									--linevec(lastv,lastdown3,8)
									break
								elseif v2.w < v1.w*0.75 then
									draw_arrow(lastup2,4,v.dir+0.25,8)
									draw_arrow(lastdown2,4,v.dir-0.25,8)
									break
								end
							end
						end
					end

					-- edges
					local track_color = (seg < current_segment-10) and 1 or track_colors[flr((seg/(mapsize/8)))%8+1]
					if seg > current_segment+5 then
						-- if it's far ahead, draw it above and scaled for parallax effect
						track_color = 1
						local segdiff = min((seg - (current_segment+5)) * 0.01,1)
						displace_line(lastup,up,camera_pos,segdiff,track_color)
						displace_line(lastdown,down,camera_pos,segdiff,track_color)
					else
						-- normal track edges
						linevec(lastup,up,track_color)
						linevec(lastdown,down,track_color)

						linevec(lastup3,up3,track_color)
						linevec(lastdown3,down3,track_color)
					end

					-- diagonals
					if seg >= current_segment-2 and seg < current_segment+7 then
						if seg % mapsize == 0 then
							linevec(lastup2,lastdown2,time < -1 and 8 or time < 0 and 9 or 11) -- start/end markers
						else
							linevec(lastup2,lastdown2,1) -- normal verticals
						end
						linevec(lastdown2,down,4)
						linevec(lastup2,up,4)
					end
				end
			end
			lastup = up
			lastdown = down
			lastup2 = up2
			lastdown2 = down2
			lastup3 = up3
			lastdown3 = down3
			lastv = v
		end

		for b in all(boosters) do
			if b.segment >= current_segment-5 and b.segment <= current_segment+5 then
				draw_arrow(b,8,b.dir,12)
			end
		end

		-- draw objects
		for obj in all(self.objects) do
			if abs(obj.current_segment-player.current_segment) <= 10 then
				if obj.trails then obj:draw_trails"" end
			end
		end
		for obj in all(self.objects) do
			if abs(obj.current_segment-player.current_segment) <= 10 then
				obj:draw""
			end
		end

		for p in all(particles) do
			line(p.x,p.y,p.x-p.xv,p.y-p.yv,p.ttl > 20 and 10 or (p.ttl > 10 and 9 or 8))
		end

		--local seg = get_segment(player.current_segment)
		--linevec(seg[1],seg[2],15)
		--linevec(seg[2],seg[3],15)
		--linevec(seg[3],seg[4],15)
		--linevec(seg[4],seg[1],15)

		camera""

		--print("mem:"..stat(0),0,0,7)
		--print("cpu:"..stat(1),0,8,7)

		-- get placing
		local placing = 1
		local nplaces = 1
		for obj in all(self.objects) do
			if obj != player then
				nplaces+=1
				if obj.current_segment > player.current_segment then
					placing+=1
				end
			end
		end
		if self.start_timer then
			player.placing = placing
		end

		print((player.placing or '?')..'/'..nplaces,0,0,9)
		local lap = flr(player.current_segment / mapsize) + 1
		if lap > 3 then
			print("lap 3/3",0,8,9)
		else
			print("lap "..lap..'/3',0,8,9)
		end
		printr(""..flr(player.speed*10),127,119,9)
		rectfill(128,123,128-40*(player.speed/15),125,9)
		rectfill(128,126,128-20*(player.accel),126,11)
		if player.cooldown > 0 then
			rectfill(128,127,128-40*(player.cooldown/30),127,2)
		else
			local c = 8
			if player.boost < boost_warning_thresh then
				c = player.boost < boost_critical_thresh and (frame%4<2 and 8 or 7) or 8
			end
			rectfill(128,127,128-(player.boost/100)*40,127,c)
		end

		print("time: "..format_time(time > 0 and time or 0),80,9,7)
		if self.best_time then
			print("best: "..format_time(self.best_time),80,3,7)
		end
		--if player.lost_count > 10 and not self.completed then
		--	print("off course",54,60,8)
		--end
		if player.wrong_way > 4 then
			print("wrong way!",54,60,8)
		end
		if time < 0 then
			print(-flr(time),60,20,8)
		end
		if player.collision > 0 or self.completed then
			-- corrupt screen
			for i=1,(completed and 100-((completed_countdown/5)*100) or 10) do
				local source = rnd(flr(0x6000+8192))
				local range = flr(rnd(64))
				local dest = 0x6000 + rnd(8192-range)-2
				memcpy(dest,source,range)
			end
			player.collision -= 0.1
		end
	end

	return race
end


function copyv(v)
	return vec(v.x,v.y)
end

function vec(x,y)
	return { x=x or 0,y=y or 0 }
end

function rotate_point(v,angle,o)
	local x,y = v.x,v.y
	local ox,oy = o.x,o.y
	return vec(
		cos(angle) * (x-ox) - sin(angle) * (y-oy) + ox,
		sin(angle) * (x-ox) + cos(angle) * (y-oy) + oy
	)
end

function cbufnew(size)
	return {_start=0,_end=0,_size=size}
end

function cbufpush(cb,v)
	-- add a value to the end of a circular buffer
	cb[cb._end] = v
	cb._end = (cb._end+1)%cb._size
	if cb._end == cb._start then
		cb._start = (cb._start+1)%cb._size
	end
end

function cbufpop(cb)
	-- remove a value from the start of the circular buffer, and return it
	local v = cb[cb._start]
	cb._start = cb._start+1%cb._size
	return v
end

function cbufget(cb,i)
	-- return a value from the circular buffer by index. 0 = start, -1 = end
	if i <= 0 then
		return cb[(cb._end - i)%cb._size]
	else
		return cb[(cb._start + i)%cb._size]
	end
end

function _update()
	game_mode:update""
end

function paused_menu(game)
	local selected = 1
	local m = {
	}
	function m:update()
		frame+=1
		if btnp(2) then selected -= 1 end
		if btnp(3) then selected += 1 end
		selected = max(min(selected,3),1)
		if btnp(4) then
			if selected == 1 then
				set_game_mode(game)
			elseif selected == 2 then
				set_game_mode(game)
				game:restart""
			elseif selected == 3 then
				set_game_mode(intro)
			end
		end
	end
	function m:draw()
		game:draw""
		rectfill(35,40,93,88,1)
		print("paused",40,44,7)
		print("continue",40,56,selected == 1 and frame%4<2 and 7 or 6)
		print("restart race",40,62,selected == 2 and frame%4<2 and 7 or 6)
		print("exit",40,70,selected == 3 and frame%4<2 and 7 or 6)
	end
	return m
end

function completed_menu(game)
	local m = {
		selected=1
	}
	function m:update()
		frame+=1
		if not btn(4) then self.ready = true end
		if btnp(2) then self.selected -= 1 end
		if btnp(3) then self.selected += 1 end
		self.selected = clamp(self.selected,1,2)
		if self.ready and btnp(4) then
			if self.selected == 1 then
				set_game_mode(game)
				game:restart""
			else
				set_game_mode(intro)
			end
		end
	end
	function m:draw()
		game:draw""
		print(difficulty_names[difficulty]..": "..cars[intro.car].name,40,32,7)
		print("race complete!",40,44,7)
		print("place: "..player.placing,40,56,7)

		print("time: "..format_time(game.time),35,70,7)
		print("best: "..format_time(game.best_time),35,78,game.best_time == game.time and frame%4<2 and 8 or 7)
		if game.previous_best then
			print("previous: "..format_time(game.previous_best),30,86,7)
		end

		print("retry",44,102,self.selected == 1 and frame%16<8 and 8 or 6)
		print("exit",44,110,self.selected == 2 and frame%16<8 and 8 or 6)
	end
	return m
end


function displace_point(p,o,factor)
	return vecadd(p,scalev(vecsub(p,o),factor))
end

function displace_line(a,b,o,factor,col)
	a = displace_point(a,o,factor)
	b = displace_point(b,o,factor)
	linevec(a,b,col)
end

function linevec(a,b,col)
	line(a.x,a.y,b.x,b.y,col)
end

-- util

function fmap(objs,func)
	local ret = {}
	for i in all(objs) do
		add(ret,func(i))
	end
	return ret
end

function clamp(val,lower,upper)
	return max(lower,min(upper,val))
end

function clampv(v,max)
	return vec(mid(-max,v.x,max),mid(-max,v.y,max))
end

function format_number(n)
	if n < 10 then return "0"..flr(n) end
	return n
end

function format_time(t)
	return format_number(flr(t))..":"..format_number(flr((t-flr(t))*60))
end

function printr(text,x,y,c)
	local l = #text
	print(text,x-l*4,y,c)
end

function dot(a,b)
	return a.x*b.x + a.y*b.y
end

function onscreen(p)
	local x = p.x
	local y = p.y
	local cx,cy = camera_pos.x,camera_pos.y
	return x >= cx - 20 and x <= cx+128+20 and y >= cy-20 and y <= cy+128+20
end

function length(v)
	return sqrt(v.x*v.x+v.y*v.y)
end

function scalev(v,s)
	return vec(v.x*s,v.y*s)
end

function normalize(v)
	local len = length(v)
	return vec(v.x/len,v.y/len)
end

function side_of_line(v1,v2,px,py)
	return (px - v1.x) * (v2.y - v1.y) - (py - v1.y)*(v2.x - v1.x)
end

function wrap(input,max)
	while input > max do input -= max end
	while input < 1 do input += max end
	return input
end

function get_vec_from_vecmap(seg)
	seg = wrap(seg,mapsize)
	local i = ((seg-1)*4)+1
	local v = {x=vecmap[i],y=vecmap[i+1],w=vecmap[i+2],dir=vecmap[i+3]}
	return v
end

function get_segment(seg,enlarge)
	seg = wrap(seg,mapsize)
	-- returns the 4 points of the segment
	local v = get_vec_from_vecmap(seg+1)
	local lastv = get_vec_from_vecmap(seg)
	local lastlastv = get_vec_from_vecmap(seg-1)

	local perp = perpendicular(normalize(vecsub(v,lastv)))
	local lastperp = perpendicular(normalize(vecsub(lastv,lastlastv)))

	local lastw = enlarge and lastv.w*2.5 or lastv.w
	local w = enlarge and v.w*2.5 or v.w
	local lastoffset = scalev(perp,lastw)
	local offset = scalev(perp,w)
	return {
		vecadd(lastv,lastoffset),
		vecsub(lastv,lastoffset),
		vecsub(v,offset),
		vecadd(v,offset),
	}
end

function perpendicular(v)
	return vec(v.y,-v.x)
end

function vecsub(a,b)
	return vec(a.x-b.x,a.y-b.y)
end

function vecadd(a,b)
	return vec(a.x+b.x,a.y+b.y)
end

function midpoint(a,b)
	return vec((a.x+b.x)/2,(a.y+b.y)/2)
end

function get_normal(a,b)
	return normalize(perpendicular(vecsub(a,b)))
end

function distance(a,b)
	return sqrt(distance2(a,b))
end

function distance2(a,b)
	local d = vecsub(a,b)
	return d.x*d.x+d.y*d.y
end

function distance_from_line2(p,v,w)
	local l2 = distance2(v,w)
	if (l2 == 0) then return distance2(p, v) end
	local t = ((p.x - v.x) * (w.x - v.x) + (p.y - v.y) * (w.y - v.y)) / l2
	if t < 0 then return distance2(p, v)
	elseif t > 1 then return distance2(p, w)
	end
	return distance2(p, vec(v.x + t * (w.x - v.x),
	                  v.y + t * (w.y - v.y)))
end

function distance_from_line(p,v,w)
	return sqrt(distance_from_line2(p,v,w))
end

function vecinv(v)
	return vec(-v.x,-v.y)
end

function point_in_polygon(pgon, t)
	local tx,ty = t.x,t.y
	local i, yflag0, yflag1, inside_flag
	local vtx0, vtx1

	local numverts = #pgon

	vtx0 = pgon[numverts]
	vtx1 = pgon[1]

	-- get test bit for above/below x axis
	yflag0 = ( vtx0.y >= ty )
	inside_flag = false

	for i=2,numverts+1 do
		yflag1=(vtx1.y>=ty)

		if yflag0 != yflag1 then
			if ((vtx1.y - ty) * (vtx0.x - vtx1.x) >= (vtx1.x - tx) * (vtx0.y - vtx1.y)) == yflag1 then
				inside_flag = not inside_flag
			end
		end

		-- move to the next pair of vertices, retaining info as possible.
		yflag0  = yflag1
		vtx0    = vtx1
		vtx1    = pgon[i]
	end

	return  inside_flag
end

function check_collision(points,lines)
	for point in all(points) do
		for line in all(lines) do
			if side_of_line(line[1],line[2],point.x,point.y) < 0 then
				local rvec = get_normal(line[1],line[2])
				local penetration = distance_from_line(point,line[1],line[2])
				return rvec,penetration,point
			end
		end
	end
	return nil
end

function lerp(a,b,t)
	return (1-t)*a+t*b
end
function lerpv(a,b,t)
	return vec(lerp(a.x,b.x,t),lerp(a.y,b.y,t))
end

function draw_arrow(p,size,dir,col)
	local v = {
		rotate_point(vecadd(p,vec(0,-size)),dir,p),
		rotate_point(vecadd(p,vec(0, size)),dir,p),
		rotate_point(vecadd(p,vec(size, 0)),dir,p)
	}
	for i=1,3 do
		linevec(v[i],v[(i%3)+1],col)
	end
end

__gfx__
00000000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
00080000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
0097f000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
0a777e00dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
00b7d000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
000c0000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
00000000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
00000000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d0000000000ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d0000000000ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d0000000000ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d0000800000ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d00097f0000ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d00a777e000ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d000b7d0000ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d0000c00000ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d0000000000ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d0000000000ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d0000000000ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d666666d666d66666d666666d66ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d666666d666d66666d666666d66ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d66dd66d666d66dddd66dd66dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d666666d666d66dddd66dd66dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d666666d666d66666d666666dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d66ddddd666d66666d666666dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d888888d888888d88888d88888d888888d99999d999999d99ddddd99999d99dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d888888d888888d88888d88888d888888d99999d999999d99ddddd99999d99dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d88dd88d88dd88d88dddd88dddd88dd88dddd99d99dd99d99ddddd99d99ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d88dd88d888888d88dddd8888dd88dd88d99999d99dd99d99999d999999d66dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d88888dd888888d88dddd8888dd88888dd99999d99dd99d99999d999999d66dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d88888dd88dd88d88dddd88dddd88888dd99dddd99dd99ddd99dd999d99d66dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d88dd88d88dd88d88888d88888d88dd88d999999999999ddd99dd999999d66dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d88dd88d88dd88d88888d88888d88dd88d999999999999ddd99dd999999d66dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd66dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d6666666666666666666666666666666666666666666666666666666666666dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd9999999999999999999999999999999999999999999
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd99999979999999777999999999999999999999999999
ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd999979799777799799799999999999999999999999999
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd9999977999999799799799999999999999999999999999
ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd99999979999999797999979999999999999999999999999
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd999999977779777797999979999999999999999999999999
999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999a999999999a9a999999999aa999a99999a999a
999999999999999999999999999999999999999999999999999999999999999999999999999999999999999a9a99aaaa9a9a99a9999999999aa999a9999aaaa9
989888889888988998889898989888889988888888999999999999999999999999999999999999999999999aa999999a9aa999a99a9aaaa9999a9999aa9a9a99
989898989898988898989898999888889986666668999999999999999999999999999999999999999999999a9999999a9a9999a9a999999999a9999a99999a99
989899989888989898989989999888889986666688999999999999999999999999999999999999999999999aaaa9aaaa9aaaa9aa99999999aa999aa9999aa999
98989998989998889888989899988888998888888899999999999999999999999999999999999999999999999999999999999999999999999999999999999999
99999999999999999999999999999999998666668899999999999999999999999999999999999999999999999999999999999999999999999999999999999999
95599555955595559599595599559955998666686899999999999999999999999999999999999999999999999999999999999999999999999999999999999999
95559595955999599599595959595955998888888899999999999999999999999999999999999999999999999999999999999999999999999999999999999999
99959595959999599595595559559959998888888899999999999999999999999999999999999999999999999999999999999999999999999999999999999999
95559555959999599555595959595955598888888899999999999999999999999999999999999999999999999999999999999999999999999999999999999999
99999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999
99999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999
99999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888866668866666666888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888888868888888866888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
__label__
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d0000000000ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d0000000000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd999dd99d99dd999dd
d0000000000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd999d9d9d9d9d9dddd
d0000800000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd9d9d9d9d9d9d99ddd
d00097f0000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd9d9d9d9d9d9d9dddd
d00a777e000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd9d9d99dd999d999dd
d000b7d0000ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d0000c00000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd666d666dd66d666ddddd6d6dd66ddddd666d666dd
d0000000000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd6d6d6d6d6ddd6ddddddd6d6d6ddddddd6d6dd6ddd
d0000000000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd66dd666d6ddd66dddddd6d6d666ddddd666dd6ddd
d0000000000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd6d6d6d6d6ddd6ddddddd666ddd6ddddd6d6dd6ddd
ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd6d6d6d6dd66d666dddddd6dd66dddddd6d6d666dd
d666666d666d66666d666666d66ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d666666d666d66666d666666d66ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d66dd66d666d66dddd66dd66dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d666666d666d66dddd66dd66dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd999d999d999dd99d9d9d
d666666d666d66666d666666ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd9dd9d9d9d9d9ddd9d9d
d66ddddd666d66666d666666ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd9dd99dd999d9ddd99dd
ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd9dd9d9d9d9d9ddd9d9d
d888888d888888d88888d88888d888888d99999d999999d99ddddd99999d99ddddddddddddddddddddddddddddddddddddddddddddddd9dd9d9d9d9dd99d9d9d
d888888d888888d88888d88888d888888d99999d999999d99ddddd99999d99dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d88dd88d88dd88d88dddd88dddd88dd88dddd99d99dd99d99ddddd99d99ddddddddddddddddddddddddddddddddd666d666d6ddd666dd66d6d6d666d66dd666d
d88dd88d888888d88dddd8888dd88dd88d99999d99dd99d99999d999999d66dddddddddddddddddddddddddddddd666d6ddd6ddd6d6d6d6d6d6d6d6d6d6d6ddd
d88888dd888888d88dddd8888dd88888dd99999d99dd99d99999d999999d66dddddddddddddddddddddddddddddd6d6d66dd6ddd66dd6d6d6d6d66dd6d6d66dd
d88888dd88dd88d88dddd88dddd88888dd99dddd99dd99ddd99dd999d99d66dddddddddddddddddddddddddddddd6d6d6ddd6ddd6d6d6d6d6d6d6d6d6d6d6ddd
d88dd88d88dd88d88888d88888d88dd88d999999999999ddd99dd999999d66dddddddddddddddddddddddddddddd6d6d666d666d666d66ddd66d6d6d6d6d666d
d88dd88d88dd88d88888d88888d88dd88d999999999999ddd99dd999999d66dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd66dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
d6666666666666666666666666666666666666666666666666666666666666dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd999d999dd99d9d9d
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd9ddd9d9d9ddd9d9d
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd99dd999d999d999d
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd9ddd9d9ddd9ddd9d
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd999d9d9d99dd999d
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddddddddddddddddd66ddddddddddddddddddddddddddddddddddddddd6d66666ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddd6d66ddddddddddddddddddddddddddddddddddddd6d66dddd6ddddddddddddddddddddddddd666ddddddddddddd666dd66dd66d666d6dddd
ddddddddddddddd6dddd6dddddddddddddddddddddddd666ddddddddd6d6ddddd6ddddddddddddddddddddddddddd6ddddddddddddd6d6d6ddd6ddd6ddd6dddd
ddddddddddddddd6dddd6d666dddddddddddddddd6666ddd6666dddddd66ddddd6dddddddddddddddddddddddddd6dddddd666ddddd666d6ddd6ddd66dd6dddd
ddddddddddddddd6dd66dd6dd6dddddddddddddd6ddddddddddd66dddd6dddddd6ddddddddddddddddddddddddd6ddddddddddddddd6d6d6ddd6ddd6ddd6dddd
ddddddddddddddd6dd6dd66dd6dddddddddddd66ddddddddddddd666dd6dddddd6ddddddddddddddddddddddddd666ddddddddddddd6d6dd66dd66d666d666dd
ddddddddddddddd6dd6ddd6d66dddddddddd66ddddddddddddddddd666dddddd6ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddddddddddddddd6dd6666d6ddddddddddd66ddddddddddddddddddd66666666dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddddddddddddddd6dddddd6ddddddddddd66dddddddddddddddddd66dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddddddddddddddd6ddddd6ddddddddddd6dddddddddddddddddd666dddddddddddddddddddddddddddddddddddd6d6ddddddddddddd666d666d666d6d6d666dd
dddddddddddddddd6dddd6ddddddddd66ddddddddddddddd6666ddddddddddddddddddddddddddddddddddddddd6d6ddddddddddddd6d6d6d6d6d6d6d6d6dddd
dddddddddddddddd6ddd6dddddddddd6dddd663366666666dddddddddddddddddddddddddddddddddddddddddddd6dddddd666ddddd66dd66dd666d66dd66ddd
dddddddddddddddd6ddd6ddddddddd6dddd6ddddddddddddddddddddddddddddddddddddddddddddddddddddddd6d6ddddddddddddd6d6d6d6d6d6d6d6d6dddd
ddddddddddddddddd6dd6ddddddddd6ddd6dddddddddddddddddddddddddddddddddddddddddddddddddddddddd6d6ddddddddddddd666d6d6d6d6d6d6d666dd
ddddddddddddddddd6d6dddddddddd6ddd6dddd66ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddddddddddddddddd6d6dddddddddd6dd6ddd66dd66ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddd6d6ddddddddd6dd6dd6ddddd6ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddd6d6ddddddddd6d6dd6ddddddd6ddddddddddddddddddddddddddddddddddddddddddd6d6d666ddddddddddddd666dd66dd66dd66d666dd
dddddddddddddddddd6dd6dddddddd666dd6ddddddd6ddddddddddddddddddddddddddddddddddddddddddd6d6d6d6ddddddddddddd6d6d6d6d6d6d6dddd6ddd
ddddddddddddddddddd6d66ddddddd66dd66ddddddd6ddddddddddddddddddddddddddddddddddddddddddd6d6d666ddddd666ddddd66dd6d6d6d6d666dd6ddd
ddddddddddddddddddd6dd666ddd66dd6d6dddddddd6ddddddddddddddddddddddddddddddddddddddddddd6d6d6ddddddddddddddd6d6d6d6d6d6ddd6dd6ddd
ddddddddddddddddddd6ddddd666dddd6d6ddddddd66dddddddddddddddddddddddddddddddddddddddddddd66d6ddddddddddddddd666d66dd66dd66ddd6ddd
ddddddddddddddddddd66dddddddddddd66dddddd66ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddd6dddddddddddd666dddd66dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddd6dddddddddddd6dd6ddd6ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddd66dddddddddd66ddd6d6ddddddddddddddddddddddddddddddddddddddddddddd6ddddd6dddddddddddddddd66d666d666d666d666dd
ddddddddddddddddddddd6dddddddddd6ddddd66dddddddddddddddddddddddddddddddddddddddddddd6ddddddd6dddddddddddddd6dddd6dd6ddd6ddd6d6dd
ddddddddddddddddddddd66dddddddd66dddd66666ddddddddddddddddddddddddddddddddddddddddd6ddddddddd6ddddd666ddddd666dd6dd66dd66dd66ddd
ddddddddddddddddddddddd6dddddd66ddddd666d66ddddddddddddddddddddddddddddddddddddddddd6ddddddd6dddddddddddddddd6dd6dd6ddd6ddd6d6dd
dddddddddddddddddddddddd666666ddddddd66ddd6dddddddddddddddddddddddddddddddddddddddddd6ddddd6ddddddddddddddd66ddd6dd666d666d6d6dd
ddddddddddddddddddddddddddddddddddddd66ddd6ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddd66d6dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddd6666dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd666d666d666ddddddddddddddddd666d666d66dd6d6dd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd6dd6d6d6d6ddddddddddddddddd666d6ddd6d6d6d6dd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd6dd666d66dddddd666ddddddddd6d6d66dd6d6d6d6dd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd6dd6d6d6d6ddddddddddddddddd6d6d6ddd6d6d6d6dd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd6dd6d6d666ddddddddddddddddd6d6d666d6d6dd66dd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd9999999999999999999999999999999999999999999
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd99999979999999777999999999999999999999999999
ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd999979799777799799799999999999999999999999999
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd9999977999999799799799999999999999999999999999
ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd99999979999999797999979999999999999999999999999
dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd999999977779777797999979999999999999999999999999
999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999a999999999a9a999999999aa999a99999a999a
999999999999999999999999999999999999999999999999999999999999999999999999999999999999999a9a99aaaa9a9a99a9999999999aa999a9999aaaa9
989888889888988998889898989888889988888888999999999999999999999999999999999999999999999aa999999a9aa999a99a9aaaa9999a9999aa9a9a99
989898989898988898989898999888889986666668999999999999999999999999999999999999999999999a9999999a9a9999a9a999999999a9999a99999a99
989899989888989898989989999888889986666688999999999999999999999999999999999999999999999aaaa9aaaa9aaaa9aa99999999aa999aa9999aa999
98989998989998889888989899988888998888888899999999999999999999999999999999999999999999999999999999999999999999999999999999999999
99999999999999999999999999999999998666668899999999999999999999999999999999999999999999999999999999999999999999999999999999999999
95599555955595559599595599559955998666686899999999999999999999999999999999999999999999999999999999999999999999999999999999999999
95559595955999599599595959595955998888888899999999999999999999999999999999999999999999999999999999999999999999999999999999999999
99959595959999599595595559559959998888888899999999999999999999999999999999999999999999999999999999999999999999999999999999999999
95559555959999599555595959595955598888888899999999999999999999999999999999999999999999999999999999999999999999999999999999999999
99999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999
99999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999
99999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888866668866666666888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888888868888888866888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
88888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888888
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

__gff__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0a80200a7e200a7e200a80200a80200a7f200a7f200a7f200a81200a7f200a7f200a7c200a7a200a7c200a7f200a83200a8120068020037e20057f200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000002525252525000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000002525252525000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0a80200a7d200a7f20067f20067920067820067820067820067d20068720068320068120068220068320068220068120068020067d20067d20067c20067c20067b20067920067f20068820068020068020067e20067d20067d20067d20068120068320038120037d20037f200000000000000000000000000000000000000000
0000002525252525252502000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000002525252525252525252525252500250000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000025252525250000000000000000002525002500252525000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0a80200a81200a81200a8a200a8a200a7c200a7d200a7f200a81200a81200a80200a82200a81200a80200a7a200a7a200a7b200a7f200a83200a83200a80200a7e200a7e200a80200a80200a7f200a7a200a87200a79200a81200a82200a8220098120047e20027c20027e200000000000000000000000000000000000000000
0000000000252525000000000000000000000000000000000000000000000000000000000000000000002525000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000252500000000000000000000000000000000000000000000000000000000000000000000000025250000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000250000000000000000000000000000000000000000000000000000000000000000000000000000250000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0a80200a80200a84200a82200a79200a84200a86200a88200a7a200a7f200a7e200a85200a82200a80200a80200a83200a80200a7a200a7a200a7a200a7a200a80200a80200a82200a84200a80200a7e200a81200a7e200a7e200a80200a80200a7f200a7b200a81200a8220077f20047f20027c20028120027e200000000000
0000000000250000000000000000000000000000000000000000000000000000000000000000000000000000000025000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000250000000000000000000000000000000000000000000000000000000000000000000000000000000025000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000252500000000000000000000000000000000000000000000000000000000000000000000000000000025000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0a8020068820038320037120037c20037d20037e20038a20038920038c20038120038020037f20037f20037f20037f20037b20037a20037720037b200390201081200371200390200370200391200383200b7e200b7d20058120058a20058a20058a20058a20057b20057f20028320028220027f20028120017c200000000000
0000000000002500000000000000000000000000000000000000000000002525252500000000000000000000000025000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000252500000000000000000000000000000000000000000000250000000025000000000000000000002500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000002500000000000000000000000000000000000000000025000000000000250000000000000000002500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0a7f200a8020037820038020038020038520038520038120038320038420038520037a20038020038020038020038020038720037c20037a20037f20038520028920147c200d82200d7e200d82200d7e200d7e20088020088320088220087e20087c20087f20088120088020087f20087f20087f20088320048420047b200480
20048b20047e20047e20047e20048520048220047f20047f20047e20047e20047820047820047820047820047820047b20048020048220048220048320048220048120038020027f20027e2001842000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000252500000000000000000000000000000000000025000000000000000000250000000000002525000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000002500000000000000000000000000000000002525000000000000000000250000000000002500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0a7f20088120088120037620038c20038620038420037820037b20037f20038b200b7e200b7920057e20058320058320048520047920067c20068220068820067d20068020068120027620027820048020047e20047d20048620047f20047a20048120048c200a7f200a7f200a82200a81200a80200a8020038a20037320037e
20088320088220087e20088120047820088520088020088220037a20088020088320087e20088820088820088820088820088020087e20087b20088920087720088920107c20107f20108420107f20107f20107520108420067d2006802103802101832200000000000000000000000000000000000000000000000000000000
0000000000000000002525000000000000000000000000002500000000000000250000000000000000002500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000025250000000000000000000000002500000000002525000000000000000000002500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0a81200a8020038a20037620038020038920037c20077e20068020067c20068020067d20068020068020068020068120068120067e20067e20067f20068120068020027220058020028b200880200b7a200b7a200b7a200b7a20048a20057c20058120058820058120058120057f20058020027620027d20028c200781200471
20098220098220026820068020068420068420068320068920068920068920068920068920068920068920068120068020068020067720067720067720067e20068620068120068020067b20068020067e20067e20068420038a20038420037d20037d20028221017f21007f2100000000000000000000000000000000000000
0000000000000000000000000000250025000000000000250000000000250000000000000000000000000025000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000025000000000000250000000000002500000000000000000000000000252500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
010c00080e3433e6153e6253e6150e3433e6153e6253e6150e373326030e6033e6430e373326033e6433e6430e373326030e6033e6430e373326033e6433e6430e37332603326033e6430e3730e3033e6433e643
01180020021750215502125021150e3050e3050e1550e125051750515505125051150e3050e305151551512513175131551312513115131051310511175111551112511115266050c60516175161551612516115
011800200e040020400e042020420e040020400e0420204211040050401104205042100400404010042040421304007040130420704215040090401504209042160400a04016042150420e040020400e04202042
013000200e5471d53715527135170e5472153711527135170e5472253713527115170e5471c53711527155170e5471d5371552713517135471c537115270e5170e54721537165271151715547225370e5270c517
011800201a302000001d302000001a302000001c302000001d302000001a302000001c302000001f302000001a30200000183021a302183021530221302183021a3011a3021d30221302213021f3011a30100000
010c00201a7551d75521755227551a7551d7552175526755267552475526755297552d7552b7552d75526755267551a75524755187551c7551d755217551f755267551a755267552b755297552d7552e7552d755
010c0020267751a775267751a775267751a775267751a775267751a775267751a77526775267752677526775287751c775287751c775267751a775267751a775297751f7752b7751d775267751c7752677518775
010c00201a7751a7050e7751d705117751d705117751d7051d7750000011775000001577500000157750000022775000001577500000137750000011775000001c7750000010775000000e775000000c77500000
011800100277402772027720277202772027720277202772020220202202022020220202202022020220202200000000000000000000000000000000000000000000000000000000000000000000000000000004
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0003000026170221701d1701917014170111700f1700c1700a1700817006170051700417003170021700117001170011000110001100051000510005100051000510005100051000410004100000000000000000
000300000117001170031700417005170061700617007170091700a1700b1700d1700f170121701517016170191701b1701d1701e17021170221701f1001f1001f1001f1001f1001f1001f1001f1001f10020100
010600080e6100e6100e6100e6100e6100e6100e6100e6100e6050e700320001a1001a100027000270002702027020270202702027020270200002000020c0020c0020c0020c002000020000200002000023c002
010600082162021620216202162021620216202162021620046020460204702047020470204702047020470200000000000000000000000000000000000000000000000000000000000000000000000000000003
0106000821120216202162021620216202162021620216203e6003e6003e6003e6003e6003e6003e6003e6003c6003c6003c6003c6003c6003c6003c6003c6003c60000600006000060000600006000060000700
000300003c65037650336503064028630196201262008610196100131000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01060008211302162021130216202162021620216202162000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003c000
000300003f6503c610276100e41312600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00020000086000221005210092200b2300e240112401334016350132501b3601f3601826023360283601c2602d360383603e3602a250223502b340373403e3402530012300103000e3000d300243002330025600
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
01 41424108
01 41024001
01 41030001
01 41030001
02 63020001
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344

