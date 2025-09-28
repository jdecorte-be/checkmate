.PHONY: install run test console clean

install:
	bundle install

run:
	bundle exec puma config.ru -p 4567

test:
	bundle exec rspec

console:
	bundle exec irb -Ilib -r./app

clean:
	rm -rf .bundle vendor/bundle
