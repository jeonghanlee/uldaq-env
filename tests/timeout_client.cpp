// Timing client for the ULDAQ network timeout configuration items.
//
// Reads one command per line from standard input and answers every command with one line on
// standard output. The elapsed time of a timed call is measured with the monotonic clock around
// the public API call only.
//
//   descriptor HOST PORT IFC   -> descriptor ERROR
//   create                     -> create ERROR
//   set ITEM VALUE             -> set ERROR            ITEM is connect or command
//   get ITEM                   -> get ERROR VALUE
//   connect                    -> connect ERROR MILLISECONDS
//   din                        -> din ERROR MILLISECONDS
//   disconnect                 -> disconnect ERROR
//   release                    -> release ERROR
//   quit                       -> exits with status 0

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <iostream>
#include <sstream>
#include <string>

#include "uldaq.h"

static double nowMs()
{
	timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);

	return ts.tv_sec * 1000.0 + ts.tv_nsec / 1000000.0;
}

static bool itemOf(const std::string& name, DevConfigItem* item)
{
	if(name == "connect")
		*item = DEV_CFG_NET_CONNECT_TIMEOUT;
	else if(name == "command")
		*item = DEV_CFG_NET_COMMAND_TIMEOUT;
	else
		return false;

	return true;
}

static void reply(const std::string& text)
{
	std::cout << text << std::endl;
}

int main()
{
	DaqDeviceDescriptor descriptor;
	DaqDeviceHandle handle = 0;
	bool haveDescriptor = false;
	std::string line;

	memset(&descriptor, 0, sizeof(descriptor));

	while(std::getline(std::cin, line))
	{
		std::istringstream words(line);
		std::string command;
		std::ostringstream out;

		words >> command;

		if(command == "descriptor")
		{
			std::string host, ifc;
			unsigned int port = 0;

			words >> host >> port >> ifc;

			UlError err = ulGetNetDaqDeviceDescriptor(host.c_str(), (unsigned short) port, ifc.c_str(), &descriptor, 2.0);
			haveDescriptor = (err == ERR_NO_ERROR);
			out << "descriptor " << err;
		}
		else if(command == "create")
		{
			handle = haveDescriptor ? ulCreateDaqDevice(descriptor) : 0;
			out << "create " << (handle ? 0 : 1);
		}
		else if(command == "set" || command == "get")
		{
			std::string name;
			DevConfigItem item;

			words >> name;

			if(!itemOf(name, &item))
			{
				reply("error unknown-item");
				continue;
			}

			if(command == "set")
			{
				long long value = 0;
				words >> value;
				out << "set " << ulDevSetConfig(handle, item, 0, value);
			}
			else
			{
				long long value = 0;
				UlError err = ulDevGetConfig(handle, item, 0, &value);
				out << "get " << err << " " << value;
			}
		}
		else if(command == "connect")
		{
			double start = nowMs();
			UlError err = ulConnectDaqDevice(handle);
			double elapsed = nowMs() - start;

			char text[64];
			snprintf(text, sizeof(text), "%.1f", elapsed);
			out << "connect " << err << " " << text;
		}
		else if(command == "din")
		{
			unsigned long long data = 0;
			double start = nowMs();
			UlError err = ulDIn(handle, FIRSTPORTA, &data);
			double elapsed = nowMs() - start;

			char text[64];
			snprintf(text, sizeof(text), "%.1f", elapsed);
			out << "din " << err << " " << text;
		}
		else if(command == "disconnect")
		{
			out << "disconnect " << ulDisconnectDaqDevice(handle);
		}
		else if(command == "release")
		{
			out << "release " << ulReleaseDaqDevice(handle);
			handle = 0;
		}
		else if(command == "quit")
		{
			return 0;
		}
		else
		{
			reply("error unknown-command");
			continue;
		}

		reply(out.str());
	}

	return 0;
}
