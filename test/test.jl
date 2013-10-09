using Iterators, Base.Test

# count
i = 0
for j = count(0, 2)
	@test j == i*2
	i += 1
	i <= 10 || break
end

# take
i = 0
for j = take(0:2:8, 10)
	@test j == i*2
	i += 1
end
@test i == 5

i = 0
for j = take(0:2:100, 10)
	@test j == i*2
	i += 1
end
@test i == 10

# drop
i = 0
for j = drop(0:2:10, 2)
	@test j == (i+2)*2
	i += 1
end
@test i == 4

# cycle
i = 0
for j = cycle(0:3)
	@test j == i % 4
	i += 1
	i <= 10 || break
end

# repeated
i = 0
for j = repeated(1, 10)
	@test j == 1
	i += 1
end
@test i == 10
i = 0
for j = repeated(1)
	@test j == 1
	i += 1
	i <= 10 || break
end

# chain
@test collect(chain(1:2:5, 0.2:0.1:1.6)) == [1:2:5, 0.2:0.1:1.6]

# product
x1 = 1:2:10
x2 = 1:5
@test collect(product(x1, x2)) == vec([(y1, y2) for y1 in x1, y2 in x2])

# distinct
x = [5, 2, 2, 1, 2, 1, 1, 2, 4, 2]
@test collect(distinct(x)) == unique(x)

# partition
@test collect(partition(take(count(1), 6), 2)) == [(1,2), (3,4), (5,6)]
@test collect(partition(take(count(1), 4), 2, 1)) == [(1,2), (2,3), (3,4)]
@test collect(partition(take(count(1), 8), 2, 3)) == [(1,2), (4,5), (7,8)]
